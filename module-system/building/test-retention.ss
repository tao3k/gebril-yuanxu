;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit trace only; ordinary module tests do not initialize retention probes.
(import :clan/poo/object
        (only-in :clan/poo/prototype-map prototype-map-length)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer
                 slot-read-key slot-read-receiver slot-read-instance slot-read-value slot-read-dependencies)
        (only-in :yuanxu/poo-clos/types ClosEffectiveMethod ClosInvocationFrame)
        (only-in :gerbil/runtime/interface interface-instance? interface-instance-object)
        (only-in :gerbil/runtime/table raw-table? &raw-table-table &raw-table-count raw-table-for-each eq-hash)
        (rename-in (only-in :gerbil/runtime/gambit table?) (table? gambit-table?))
        (only-in :gerbil/expander current-expander-compile current-expander-context
                 current-expander-phi expander-context? module-context? module-context-path
                 module-context-code expander-context-table)
        (only-in :yuanxu/observability/testing-case yuanxu-test-observe)
        (only-in :yuanxu/observability/memory yuanxu-debug-cpu-microseconds)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer))
(export observe-read-dependencies)

;; Trace the existing native dependency records without retaining tokens,
;; receivers or values. Run inside the Case so refusal still emits the totals.
(def (observe-read-dependencies thunk)
  (def deliveries 0)
  (def edges 0)
  (def largest 0)
  ;; Weak diagnostic identities are not a result cache or a retention owner.
  ;; Entries may disappear at GC. Payload inspection below is cache-only and
  ;; does not construct a frame, demand a Type prototype or invoke a MOP hook.
  (def clos-values (make-hash-table-eq weak-keys: #t))
  (def clos-reads (make-hash-table-eq weak-keys: #t))
  ;; Native Reader objects are weak diagnostic keys, never source/Graph roots.
  ;; Keep only closed role labels as values; compiled code is not an input cache.
  (def reader-contexts (make-hash-table-eq weak-keys: #t))
  (def reader-forms (make-hash-table-eq weak-keys: #t))
  (def reader-programs (make-hash-table-eq weak-keys: #t))
  (def native-compile (current-expander-compile))
  (def (reader-role context)
    (and (module-context? context) (zero? (current-expander-phi))
         (let (path (module-context-path context))
           (and (string? path)
                (or (string-contains path "publication-reader-")
                    (string-contains path "configuration-reader-"))
                (cond
                  ((string-suffix? "-interface.ss" path) 'interface)
                  ((string-suffix? "-types.ss" path) 'types)
                  ((string-suffix? "-objects.ss" path) 'objects)
                  ((string-suffix? "-config.ss" path) 'config)
                  (else 'private))))))
  (def (observe-compile form)
    (def context (current-expander-context))
    (def role (reader-role context))
    (def body? (and role (eq? form (module-context-code context))))
    (when body?
      (hash-put! reader-contexts context role)
      (hash-put! reader-forms form role))
    (let (program (native-compile form))
      (when (and body? (pair? program)) (hash-put! reader-programs program role))
      program))
  (def (report-reader-roots)
    (def rows (make-hash-table-eq))
    (def (row role)
      (or (hash-get rows role)
          (let (value (vector 0 0 0 0 0)) (hash-put! rows role value) value)))
    (hash-for-each
      (lambda (context role)
        (def value (row role))
        (vector-set! value 0 (+ 1 (vector-ref value 0)))
        (vector-set! value 1 (+ (hash-length (expander-context-table context)) (vector-ref value 1)))
        (when (module-context-code context)
          (vector-set! value 2 (+ 1 (vector-ref value 2))))) reader-contexts)
    (hash-for-each (lambda (_form role)
                    (def value (row role))
                    (vector-set! value 3 (+ 1 (vector-ref value 3)))) reader-forms)
    (hash-for-each (lambda (_program role)
                    (def value (row role))
                    (vector-set! value 4 (+ 1 (vector-ref value 4)))) reader-programs)
    (hash-for-each
      (lambda (role value)
        (yuanxu-write-observation-line!
          "reader-gerbil-roots role=%s contexts=%s bindings=%s code-bodies=%s expanded=%s programs=%s"
          role (vector-ref value 0) (vector-ref value 1) (vector-ref value 2)
          (vector-ref value 3) (vector-ref value 4))) rows))
  (def publications 0)
  (def next-snapshot 1)
  (def source-observer (current-module-source-observer))
  (def (cached-prototype descriptor)
    (def fields (object-%instance descriptor))
    (and fields (hash-get fields 'proto)))
  (def (cached-clos-kind receiver)
    (def order (object-%precedence-list receiver))
    (def effective (cached-prototype ClosEffectiveMethod))
    (def frame (cached-prototype ClosInvocationFrame))
    (cond
     ((and effective (pair? order) (memq effective order)) 'poo-clos/effective-method)
     ((and frame (pair? order) (memq frame order)) 'poo-clos/invocation-frame)
     (else #f)))
  (def (cached-receiver-kind receiver)
    ;; Diagnostic attribution only. Read an ALREADY allocated native instance;
    ;; never instantiate it, invoke a getter/MOP hook or grant admission.
    (def instance (and (object? receiver) (object-%instance receiver)))
    (def kind (and instance (hash-get instance 'kind)))
    (if (memq kind '(yuanxu.type.classification-evidence
                     yuanxu.contract.validation-evidence
                     yuanxu.module-authoring.admission
                     yuanxu.module-authoring.diagnostic
                     poo-clos/generic-function poo-clos/effective-method
                     poo-clos/invocation-frame)) kind
      (or (and (object? receiver) (cached-clos-kind receiver)) 'unclassified)))
  (def (report-clos-roots)
    (def frames 0)
    (def effective 0)
    (def arguments 0)
    (def continuations 0)
    (def argument-lists (make-hash-table-eq))
    (def argument-cells (make-hash-table-eq))
    (def next-closures (make-hash-table-eq))
    (def shared-frame-arguments 0)
    (def separate-frame-arguments 0)
    (def next-cells 0)
    (def (observe-arguments args)
      ;; Read existing pair identities only. Never copy/merge a call's payload,
      ;; walk argument values or construct evidence inside this observer.
      (let walk ((tail args))
        (when (and (pair? tail) (not (hash-key? argument-cells tail)))
          (hash-put! argument-cells tail #t)
          (walk (cdr tail)))))
    (def authoring-interfaces (make-hash-table-eq))
    (def authoring-datums (make-hash-table-eq))
    (hash-for-each
      (lambda (value kind)
        (def instance (object-%instance value))
        (when instance
          (case kind
            ((poo-clos/effective-method) (set! effective (+ effective 1)))
            ((poo-clos/invocation-frame) (set! frames (+ frames 1))))
          (let (args (hash-get instance 'arguments))
            (when (list? args)
              (set! arguments (+ arguments (length args)))
              (hash-put! argument-lists args #t)
              (observe-arguments args)
              (when (eq? kind 'poo-clos/invocation-frame)
                (let* ((effective (hash-get instance 'effective-method))
                       (fields (and (object? effective) (object-%instance effective))))
                  (if (and fields (eq? args (hash-get fields 'arguments)))
                    (set! shared-frame-arguments (+ 1 shared-frame-arguments))
                    (set! separate-frame-arguments (+ 1 separate-frame-arguments)))))
              (let* ((effective (if (eq? kind 'poo-clos/effective-method) value
                                 (hash-get instance 'effective-method)))
                     (fields (and (object? effective) (object-%instance effective)))
                     (generic (and fields (hash-get fields 'generic)))
                     (metadata (and (object? generic) (object-%instance generic))))
                (when (and metadata
                           (eq? (hash-get metadata 'identity) 'module-authoring-analyze)
                           (= (length args) 4))
                  (hash-put! authoring-interfaces (caddr args) #t)
                  (hash-put! authoring-datums (cadddr args) #t)))))
        (when (and instance (procedure? (hash-get instance 'next)))
          (set! continuations (+ continuations 1))
          (let (next (hash-get instance 'next))
            (when (and (##closure? next) (not (hash-key? next-closures next)))
              (hash-put! next-closures next #t)
              ;; Shallow cells, not transitive bytes. Do not inspect or execute
              ;; the callback's captured values, including external user state.
              (set! next-cells (+ next-cells (1- (##closure-length next))))))))) clos-values)
    (yuanxu-write-observation-line!
      "reader-clos-roots publications=%s effective=%s frames=%s argument-refs=%s argument-lists=%s authoring-interfaces=%s authoring-datums=%s continuations=%s read-records=%s"
      publications effective frames arguments (hash-length argument-lists)
      (hash-length authoring-interfaces) (hash-length authoring-datums)
      continuations (hash-length clos-reads))
    (yuanxu-write-observation-line!
      "reader-call-payload argument-spines=%s argument-cells=%s frames-sharing-effective-args=%s frames-with-own-args=%s next-closures=%s next-cells=%s"
      (hash-length argument-lists) (hash-length argument-cells)
      shared-frame-arguments separate-frame-arguments
      (hash-length next-closures) next-cells))
  (def (observe-source key amount)
    (when (and (pair? key) (eq? (car key) 'publication-end))
      (set! publications (+ publications amount))
      (when (>= publications next-snapshot)
        (report-clos-roots)
        (report-reader-roots)
        (set! next-snapshot (* 2 next-snapshot))))
    (when source-observer (source-observer key amount)))
  (def (cached-contract-label instance)
    ;; Attribute receipts through already cached actual Contract references.
    ;; Closed scalar labels only: no getter, binding, descriptor or candidate
    ;; escapes. A missing cache entry is unknown, never guessed from a name.
    (def contract (hash-get instance 'admission-contract))
    (def fields (and (object? contract) (object-%instance contract)))
    (def identity (and fields (hash-get fields 'identity)))
    (if (memq identity '(semantic-symbol semantic-symbol-list semantic-object
                         semantic-boolean module-source-role module-authoring-profile))
      identity 'other-contract))
  (def (report-dependency-support root)
    ;; Trace-only, one completed selected Graph. Follow ORIGINAL native suffixes
    ;; without getters; identities never escape this temporary diagnostic walk.
    (def seen (make-hash-table-eq))
    (def receivers (make-hash-table-eq))
    (def rows (make-hash-table-eq))
    ;; Inspect only the registered issuer's compiled closure family. Never walk
    ;; user payloads, execute a checker, or follow Gerbil/weak-registry internals.
    (def births (make-hash-table-eq))
    (def birth-cells 0)
    (def singleton-snapshots (make-hash-table-eq))
    (def (birth! read)
      (defvalues (_presented original _signed _snapshot _shape) (object-read-issuance read))
      ;; Count retained issuer captures, not the inspector's fresh copy. The
      ;; value is excluded so a user's one-element vector is not a snapshot.
      (let (parents (slot-read-dependencies read))
        (when (and original (##closure? original) (pair? parents) (null? (cdr parents)))
          (let fields ((index (1- (##closure-length original))))
            (when (> index 0)
              (let (field (##closure-ref original index))
                (when (and (vector? field) (= (vector-length field) 1)
                           (not (eq? field (slot-read-value read)))
                           (eq? (vector-ref field 0) (car parents)))
                  (hash-put! singleton-snapshots field #t)))
              (fields (1- index))))))
      (when (and original (##closure? original))
        (let (owner (##subprocedure-parent (##closure-ref original 0)))
          (let walk ((pending (list original)))
            (unless (null? pending)
              (let ((head (car pending)) (tail (cdr pending)))
                (if (and (##closure? head) (not (hash-key? births head))
                         (eq? owner (##subprocedure-parent (##closure-ref head 0))))
                  (begin
                    (hash-put! births head #t)
                    ;; Index zero is compiled code, not a captured field.
                    (set! birth-cells (+ birth-cells (1- (##closure-length head))))
                    (let fields ((index (1- (##closure-length head))) (rest tail))
                      (if (< index 1) (walk rest)
                        (fields (1- index) (cons (##closure-ref head index) rest)))))
                  (walk tail))))))))
    ;; Exact retained reference routes, not an estimated transitive byte size.
    ;; Inspect only native raw tables; never dispatch an unknown HashTable API.
    (def instances (make-hash-table-eq))
    (def tables (make-hash-table-eq))
    (def cells (make-hash-table-eq))
    (def callbacks (make-hash-table-eq))
    (def direct-objects (make-hash-table-eq))
    (def callback-objects (make-hash-table-eq))
    (def strings (make-hash-table-eq))
    (def vectors (make-hash-table-eq))
    (def metadata-tables (make-hash-table-eq))
    (def metadata-callbacks (make-hash-table-eq))
    (def specification-roots (make-hash-table-eq))
    (def metadata-entries 0)
    (def metadata-backing-cells 0)
    (def metadata-callback-cells 0)
    (def metadata-receiver-captures 0)
    (def warm-thunks (make-hash-table-eq))
    (def cold-thunks (make-hash-table-eq))
    (def warm-entries 0)
    (def cold-entries 0)
    (def unknown-entries 0)
    (def cold-protocol-entries 0)
    (def cold-declaration-entries 0)
    (def cold-bare-entries 0)
    ;; Trace-only transitive raw payload accounting. Never force a slot, promise,
    ;; interface method or checker. Receiver and Gerbil context identities are
    ;; frontiers, not recursively expanded into the entire running process.
    (def expander-contexts (make-hash-table-eq))
    ;; Raw shell projection never invokes a getter or prepares a receiver.
    ;; Descriptors are external roots, and nested owner contexts remain boundaries.
    (def (shell-fields value)
      (def type (##structure-type value))
      (let loop ((index (1- (##structure-length value))) (result '()))
        (if (< index 1) result
          (loop (1- index)
            (cons (##structure-ref value index type #f) result)))))
    (def (deep-payload roots label (structural? #f))
      (def progress-scope (gensym 'classified-payload-nodes))
      (def visited (make-hash-table-eq))
      (def frontiers (make-hash-table-eq))
      (def kinds (make-hash-table-eq))
      (def words 0)
      (def references 0)
      (def repeated 0)
      (def closures 0)
      (def characters 0)
      (def (fields value length ref)
        (let loop ((index (1- length)) (result '()))
          (if (< index 0) result
            (loop (1- index) (cons (ref value index) result)))))
      (let walk ((pending roots))
        (unless (null? pending)
          (let ((value (car pending)) (tail (cdr pending)))
          (cond
            ((or (object? value) (expander-context? value) (class-type? value)
                 ;; Weak tables are not strong retention edges. Do not walk
                 ;; any Gambit/GC table until its ephemeron policy is modeled.
                 (gambit-table? value)
                 (and (##structure? value)
                   (##structure-instance-of? value 'gerbil#__gc-table::t)))
             (when (expander-context? value) (hash-put! expander-contexts value #t))
             (hash-put! frontiers value #t) (walk tail))
            ((and structural?
               (or (##closure? value)
                 (and (##structure? value)
                   (not (memq (##type-id (##structure-type value))
                     '(clan/poo/prototype-map#specifications::t
                       std/struct/rbtree#RBTree::t std/struct/rbtree#Tree::t
                       std/struct/rbtree#Empty::t))))))
             (hash-put! frontiers value #t) (walk tail))
            ((or (pair? value) (vector? value) (string? value)
                 (##closure? value) (##structure? value))
             (if (hash-key? visited value)
               (begin (set! repeated (1+ repeated)) (walk tail))
               (begin
                 (hash-put! visited value #t)
                 ;; Actual newly discovered identities, never timer ticks.
                 ;; This trace-only walk leaves native deliveries untouched.
                 (when (zero? (modulo (hash-length visited) 1024))
                   (execution-progress! progress-scope (hash-length visited)))
                 (cond
                   ((pair? value)
                    (set! words (+ words 2))
                    (set! references (+ references 2))
                    (walk (cons (car value) (cons (cdr value) tail))))
                   ((string? value)
                    (set! characters (+ characters (string-length value))) (walk tail))
                   ((vector? value)
                    (set! words (+ words (vector-length value)))
                    (set! references (+ references (vector-length value)))
                    (walk (append (fields value (vector-length value) vector-ref) tail)))
                   ((##closure? value)
                    (set! closures (1+ closures))
                    (set! words (+ words (##closure-length value)))
                    ;; Code at index zero is an opaque executable, not an env.
                    (set! references (+ references (1- (##closure-length value))))
                    (walk (append (cdr (fields value (##closure-length value) ##closure-ref)) tail)))
                   (else
                    (let (type (##structure-type value))
                    (hash-update! kinds (##type-id type) 1+ 0)
                    (set! words (+ words (##structure-length value)))
                    ;; Do not traverse the class descriptor at offset zero.
                    (set! references (+ references (1- (##structure-length value))))
                    (walk (append
                      (let loop ((index (1- (##structure-length value))) (result '()))
                        (if (< index 1) result
                          (loop (1- index)
                            (cons (##structure-ref value index type #f) result)))) tail))))))))
            (else (walk tail))))))
      (yuanxu-write-observation-line!
        "slot-deep-payload kind=%s nodes=%s words=%s closures=%s references=%s repeated-identities=%s frontier=%s string-characters=%s top-structures=%s"
        label (hash-length visited) words closures references repeated (hash-length frontiers) characters
        (take (list-sort (lambda (a b) (> (cdr a) (cdr b))) (hash->list kinds))
          (min 8 (hash-length kinds))))
      visited)
    (def stale-instances 0)
    (def unknown-instances 0)
    (def table-entries 0)
    (def table-cells 0)
    (def callback-cells 0)
    (def opaque-closure-captures 0)
    (def string-characters 0)
    (def vector-cells 0)
    (def (native-table value)
      (let (raw (if (interface-instance? value) (interface-instance-object value) value))
        (and (raw-table? raw) raw)))
    (def (observe-pairs value)
      (let walk ((tail value))
        (when (and (pair? tail) (not (hash-key? cells tail)))
          (hash-put! cells tail #t)
          (when (object? (car tail)) (hash-put! direct-objects (car tail) #t))
          (walk (cdr tail)))))
    (def (observe-shallow value callback?)
      (cond
        ((object? value)
         (hash-put! direct-objects value #t)
         (when callback? (hash-put! callback-objects value #t)))
        ((native-table value) =>
         (lambda (table)
           (unless (hash-key? tables table)
             (hash-put! tables table #t)
             (set! table-entries (+ table-entries (&raw-table-count table)))
             (set! table-cells (+ table-cells (vector-length (&raw-table-table table)))))))
        ((pair? value) (observe-pairs value))
        ((string? value)
         (unless (hash-key? strings value)
           (hash-put! strings value #t)
           (set! string-characters (+ string-characters (string-length value)))))
        ((vector? value)
         (unless (hash-key? vectors value)
           (hash-put! vectors value #t)
           (set! vector-cells (+ vector-cells (vector-length value)))))))
    (def (observe-callback value)
      (when (and (##closure? value) (not (hash-key? callbacks value)))
        (hash-put! callbacks value #t)
        (set! callback-cells (+ callback-cells (1- (##closure-length value))))
        (let fields ((index (1- (##closure-length value))))
          (when (> index 0)
            (let (captured (##closure-ref value index))
              ;; Nested closures are opaque; their environment can contain
              ;; unrelated user state. Never invoke or recursively inspect it.
              (if (##closure? captured)
                (set! opaque-closure-captures (+ opaque-closure-captures 1))
                (observe-shallow captured #t)))
            (fields (1- index))))))
    (def (observe-instance read)
      (def instance (slot-read-instance read))
      (when instance
        (unless (eq? instance (object-%instance (slot-read-receiver read)))
          (set! stale-instances (+ 1 stale-instances)))
        (unless (hash-key? instances instance)
          (hash-put! instances instance #t)
          (let (raw (native-table instance))
            (if raw
              (begin
                (observe-shallow instance #f)
                (raw-table-for-each raw
                  (lambda (_key value)
                    (observe-shallow value #f)
                    (observe-callback value))))
              (set! unknown-instances (+ 1 unknown-instances)))))))
    (def (observe-receiver-metadata receiver)
      ;; These are raw struct fields, not public computed getters. Count only
      ;; already assembled metadata; do not prepare a receiver to inspect it.
      (for-each (lambda (root)
        (when root (hash-put! specification-roots root #t)))
        (list (object-%slots receiver) (object-%defaults receiver)))
      (observe-pairs (object-%precedence-list receiver))
      (observe-pairs (object-%all-slots receiver))
      (let* ((cached (object-%slot-funs receiver))
             (table (and cached (native-table cached)))
             (values-table (and table (native-table (object-%instance receiver))))
             (value-keys (and values-table (make-hash-table-eq)))
             (precedence (object-%precedence-list receiver))
             (has-protocol (and (pair? precedence) (ormap object-%protocol precedence)))
             (has-declarations (and (pair? precedence)
               (ormap (lambda (parent) (positive? (prototype-map-length (object-%declarations parent)))) precedence))))
        (when (and table (not (hash-key? metadata-tables table)))
          (hash-put! metadata-tables table #t)
          (set! metadata-entries (+ metadata-entries (&raw-table-count table)))
          (set! metadata-backing-cells
            (+ metadata-backing-cells (vector-length (&raw-table-table table))))
          ;; Enumerate raw keys rather than dispatching ref/hash callbacks on
          ;; a receiver-owned table. This diagnostic never forces a slot.
          (when values-table
            (raw-table-for-each values-table
              (lambda (key _) (hash-put! value-keys key #t))))
          (raw-table-for-each table
            (lambda (key fun)
              (cond
                ((not values-table) (set! unknown-entries (1+ unknown-entries)))
                ((hash-key? value-keys key)
                 (set! warm-entries (1+ warm-entries))
                 (when (##closure? fun) (hash-put! warm-thunks fun #t)))
                (else
                 (set! cold-entries (1+ cold-entries))
                 (when has-protocol (set! cold-protocol-entries (1+ cold-protocol-entries)))
                 (when has-declarations (set! cold-declaration-entries (1+ cold-declaration-entries)))
                 (when (and (pair? precedence) (not has-protocol) (not has-declarations))
                   (set! cold-bare-entries (1+ cold-bare-entries)))
                 (when (##closure? fun) (hash-put! cold-thunks fun #t))))
              (when (and (##closure? fun) (not (hash-key? metadata-callbacks fun)))
                (hash-put! metadata-callbacks fun #t)
                (set! metadata-callback-cells
                  (+ metadata-callback-cells (1- (##closure-length fun))))
                (let fields ((index (1- (##closure-length fun))))
                  (when (> index 0)
                    (let (captured (##closure-ref fun index))
                      (when (eq? captured receiver)
                        (set! metadata-receiver-captures (+ metadata-receiver-captures 1)))
                      ;; Only observe the immediate payload. Do not recurse
                      ;; through interpreter closures, specs or user objects.
                      (unless (##closure? captured) (observe-shallow captured #f)))
                    (fields (1- index))))))))))
    (def edges 0)
    (def widest 0)
    (def widest-key #f)
    (let walk ((pending (list root)))
      (unless (null? pending)
        (let (read (car pending))
          (if (hash-key? seen read) (walk (cdr pending))
            (let* ((dependencies (slot-read-dependencies read))
                   (width (length dependencies))
                   (key (slot-read-key read))
                   (label (if (symbol? key) key 'structural-query)))
              (hash-put! seen read #t)
              (birth! read)
              (observe-instance read)
              (unless (hash-key? receivers (slot-read-receiver read))
                (observe-receiver-metadata (slot-read-receiver read)))
              (hash-put! receivers (slot-read-receiver read) #t)
              (hash-update! rows label (cut + <> width) 0)
              (set! edges (+ edges width))
              (when (> width widest) (set! widest width) (set! widest-key label))
              (walk (append dependencies (cdr pending))))))))
    (yuanxu-write-observation-line!
      "slot-transitive-support tokens=%s receivers=%s edges=%s widest=%s widest-key=%s top-edge-owners=%s"
      (hash-length seen) (hash-length receivers) edges widest widest-key
      (take (list-sort (lambda (left right) (> (cdr left) (cdr right))) (hash->list rows))
        (min 8 (hash-length rows))))
    (yuanxu-write-observation-line!
      "slot-issuer-storage records=%s closures=%s captured-cells=%s singleton-parent-vectors=%s"
      (hash-length seen) (hash-length births) birth-cells (hash-length singleton-snapshots))
    (yuanxu-write-observation-line!
      "slot-receiver-metadata specification-roots=%s thunk-tables=%s entries=%s backing-cells=%s thunks=%s captured-cells=%s direct-own-receiver-captures=%s"
      (hash-length specification-roots) (hash-length metadata-tables)
      metadata-entries metadata-backing-cells (hash-length metadata-callbacks)
      metadata-callback-cells metadata-receiver-captures)
    (let ((only-cold 0) (shared-warm 0) (cold-fields 0))
      (hash-for-each (lambda (fun _)
        (if (hash-key? warm-thunks fun) (set! shared-warm (1+ shared-warm))
          (begin
            (set! only-cold (1+ only-cold))
            (set! cold-fields (+ cold-fields (1- (##closure-length fun))))))) cold-thunks)
      (yuanxu-write-observation-line!
        "slot-thunk-demand warm-entries=%s cold-entries=%s unknown-entries=%s cold-only-identities=%s shared-with-warm=%s cold-only-capture-fields=%s cold-protocol-entries=%s cold-declaration-entries=%s cold-bare-entries=%s"
        warm-entries cold-entries unknown-entries only-cold shared-warm cold-fields
        cold-protocol-entries cold-declaration-entries cold-bare-entries))
    ;; Distinct closures may repeat the SAME capture identity sequence. Hash
    ;; only primitive identity codes, then compare every field (including code)
    ;; on collision. Never invoke a thunk or merge the original functions.
    (let ((buckets (make-hash-table)) (families (make-hash-table-eq))
          (duplicates 0) (duplicate-fields 0))
      (def (same-captures? left right)
        (and (= (##closure-length left) (##closure-length right))
          (let loop ((index (1- (##closure-length left))))
            (or (< index 0)
              (and (eq? (##closure-ref left index) (##closure-ref right index))
                (loop (1- index)))))))
      (hash-for-each (lambda (fun _)
        (def signature
          (let loop ((index (1- (##closure-length fun))) (value 0))
            (if (< index 0) value
              (loop (1- index)
                (modulo (+ (* value 65599) (eq-hash (##closure-ref fun index))) 536870909)))))
        (def bucket (or (hash-get buckets signature) '()))
        (def duplicate? (any (cut same-captures? fun <>) bucket))
        (def name (##subprocedure-parent-name (##closure-ref fun 0)))
        (def label (if (symbol? name) name 'unnamed))
        (def row (or (hash-get families label)
          (let (row (vector 0 0 0)) (hash-put! families label row) row)))
        (vector-set! row 0 (1+ (vector-ref row 0)))
        (if duplicate?
          (begin
            (set! duplicates (1+ duplicates))
            (set! duplicate-fields (+ duplicate-fields (1- (##closure-length fun))))
            (vector-set! row 2 (+ (vector-ref row 2) (1- (##closure-length fun)))))
          (begin
            (vector-set! row 1 (1+ (vector-ref row 1)))
            (hash-put! buckets signature (cons fun bucket))))) metadata-callbacks)
      (yuanxu-write-observation-line!
        "slot-thunk-captures repeated-environments=%s repeated-fields=%s families=%s"
        duplicates duplicate-fields (hash->list families)))
    (let* ((specs (deep-payload (hash-keys specification-roots) 'specifications))
           (thunks (deep-payload (hash-keys metadata-callbacks) 'thunk-environments))
           (shared 0))
      (deep-payload (hash-keys specification-roots) 'specification-structure #t)
      (hash-for-each (lambda (node _)
        (when (hash-key? specs node)
          (set! shared (1+ shared)))) thunks)
      (yuanxu-write-observation-line! "slot-deep-intersection nodes=%s" shared)
      ;; One-hop owner expansion. The closure walk still stops at every nested
      ;; receiver/context, weak table and descriptor: no whole-process crawl.
      (let* ((receiver-payload
               (deep-payload (apply append (map shell-fields (hash-keys receivers)))
                 'receiver-shell-payload))
             (context-count (hash-length expander-contexts))
             (context-payload
               (deep-payload (apply append (map shell-fields (hash-keys expander-contexts)))
                 'expander-context-shell-payload))
             (union (make-hash-table-eq)))
        (def union-scope (gensym 'classified-union-nodes))
        (def union-work 0)
        (def (union-step!)
          (set! union-work (1+ union-work))
          (when (zero? (modulo union-work 1024))
            (execution-progress! union-scope union-work)))
        (for-each
          (lambda (entry)
            (let ((label (car entry)) (nodes (cdr entry)) (overlap 0) (added 0))
              (hash-for-each (lambda (node _)
                (union-step!)
                (if (hash-key? union node) (set! overlap (1+ overlap))
                  (begin (hash-put! union node #t) (set! added (1+ added))))) nodes)
              (yuanxu-write-observation-line!
                "slot-payload-union kind=%s overlap=%s added=%s union=%s"
                label overlap added (hash-length union))))
          (list (cons 'specifications specs) (cons 'thunks thunks)
            (cons 'receiver-shell receiver-payload)))
        ;; Count the final union by intersection; do not copy the million-node
        ;; Gerbil support into a second table. Both tables enumerate unique ids.
        (let ((shared 0)
              (smaller (if (< (hash-length union) (hash-length context-payload))
                         union context-payload))
              (larger (if (< (hash-length union) (hash-length context-payload))
                        context-payload union)))
          (hash-for-each (lambda (node _)
            (union-step!)
            (when (hash-key? larger node) (set! shared (1+ shared)))) smaller)
          (yuanxu-write-observation-line!
            "slot-payload-union kind=expander-shell overlap=%s added=%s union=%s scanned=%s"
            shared (- (hash-length context-payload) shared)
            (- (+ (hash-length union) (hash-length context-payload)) shared)
            (hash-length smaller)))
        (yuanxu-write-observation-line!
          "slot-owner-shells receivers=%s expander-contexts=%s nested-policy=frontier exclusive-bytes=unknown"
          (hash-length receivers) context-count)))
    (let ((known-targets 0) (callback-targets 0))
      (hash-for-each (lambda (target _)
        (when (hash-key? receivers target) (set! known-targets (+ known-targets 1)))) direct-objects)
      (hash-for-each (lambda (target _)
        (when (hash-key? receivers target) (set! callback-targets (+ callback-targets 1)))) callback-objects)
      (yuanxu-write-observation-line!
        "slot-retained-payload instances=%s noncurrent-instance-records=%s unknown-instances=%s native-tables=%s entries=%s backing-cells=%s list-cells=%s object-targets=%s known-receiver-targets=%s callbacks=%s callback-cells=%s callback-receiver-targets=%s opaque-closure-captures=%s strings=%s characters=%s vectors=%s vector-cells=%s"
        (hash-length instances) stale-instances unknown-instances
        (hash-length tables) table-entries table-cells (hash-length cells)
        (hash-length direct-objects) known-targets (hash-length callbacks) callback-cells callback-targets
        opaque-closure-captures (hash-length strings) string-characters
        (hash-length vectors) vector-cells)))
  (def (observe read)
    (def receiver (slot-read-receiver read))
    (when (object? receiver)
      (let (kind (cached-clos-kind receiver))
        (when kind
          (hash-put! clos-values receiver kind)
          (hash-put! clos-reads read #t))))
    (def width (length (slot-read-dependencies read)))
    (when (and (eq? (slot-read-key read) 'selected-graph) (>= width 128))
      (report-dependency-support read))
    (set! deliveries (+ deliveries 1))
    (set! edges (+ edges width))
    (when (> width largest)
      (when (and (>= width 128) (>= width (* 2 (max 1 largest))))
        ;; A transient identity census only at geometrically larger widths.
        ;; Discard it before returning; no token/receiver escapes into telemetry.
        (let ((unique (make-hash-table-eq)) (receivers (make-hash-table-eq))
              (keys (make-hash-table)) (kinds (make-hash-table-eq))
              (contracts (make-hash-table-eq)) (context-free 0) (context-unknown 0))
          (for-each
            (lambda (dependency)
              (def receiver (slot-read-receiver dependency))
              (def previous-kind (hash-get receivers receiver))
              (def kind (or previous-kind (cached-receiver-kind receiver)))
              (def kind-row (or (hash-get kinds kind) (vector 0 0 0)))
              (vector-set! kind-row 0 (+ (vector-ref kind-row 0) 1))
              (unless previous-kind
                (hash-put! receivers receiver kind)
                (vector-set! kind-row 2 (+ (vector-ref kind-row 2) 1))
                (when (eq? kind 'yuanxu.contract.validation-evidence)
                  (let* ((instance (object-%instance receiver))
                         (label (cached-contract-label instance)))
                    (hash-update! contracts label (cut + <> 1) 0)
                    (cond
                     ((not (hash-key? instance 'context))
                      (set! context-unknown (+ context-unknown 1)))
                     ((not (hash-get instance 'context))
                      (set! context-free (+ context-free 1)))))))
              (def native-key (slot-read-key dependency))
              (def label
                (cond
                 ((symbol? native-key) native-key)
                 ((and (pair? native-key)
                       (or (equal? native-key '(names))
                           (and (memq (car native-key) '(presence bootstrap cache-miss))
                                (pair? (cdr native-key)) (symbol? (cadr native-key))
                                (null? (cddr native-key))))) native-key)
                 (else 'other)))
              (def key (if (or (hash-key? keys label) (< (hash-length keys) 128)) label 'other))
              (def row (or (hash-get keys key) (vector 0 0)))
              (vector-set! row 0 (+ (vector-ref row 0) 1))
              (unless (hash-key? unique dependency)
                (hash-put! unique dependency #t)
                (vector-set! kind-row 1 (+ (vector-ref kind-row 1) 1))
                (vector-set! row 1 (+ (vector-ref row 1) 1)))
              (hash-put! kinds kind kind-row)
              (hash-put! keys key row))
            (slot-read-dependencies read))
          (yuanxu-write-observation-line! "slot-dependency-width key=%s edges=%s distinct=%s"
            (let (key (slot-read-key read)) (if (symbol? key) key 'structural-query))
            width (hash-length unique))
          ;; Only the eight largest scalar key rows escape. The transient
          ;; receiver/token identity tables die before this observer returns.
          (yuanxu-write-observation-line! "slot-dependency-owners key=%s receivers=%s top-keys=%s"
            (let (key (slot-read-key read)) (if (symbol? key) key 'structural-query))
            (hash-length receivers)
            (map (lambda (entry)
                   (list (car entry) (vector-ref (cdr entry) 0) (vector-ref (cdr entry) 1)))
              (take (list-sort (lambda (a b) (> (vector-ref (cdr a) 0) (vector-ref (cdr b) 0)))
                              (hash->list keys))
                    (min 8 (hash-length keys)))))
          (yuanxu-write-observation-line! "slot-dependency-kinds key=%s rows=%s"
            (let (key (slot-read-key read)) (if (symbol? key) key 'structural-query))
            (map (lambda (entry)
                   (cons (car entry) (vector->list (cdr entry)))) (hash->list kinds)))
          (yuanxu-write-observation-line! "slot-dependency-contracts key=%s context-free=%s context-unknown=%s rows=%s"
            (let (key (slot-read-key read)) (if (symbol? key) key 'structural-query))
            context-free context-unknown (hash->list contracts))))
      (set! largest width)))
  (dynamic-wind void
    (lambda ()
      (parameterize ((current-module-source-observer observe-source)
                     (current-expander-compile observe-compile))
        (call-with-slot-read-observer observe thunk)))
    (lambda ()
      ;; A bounded three-scalar receipt, not three additional dynamic work
      ;; categories. Preserve the Case's existing 64-category bound and never
      ;; mask a domain failure while unwinding the observation scope.
      (yuanxu-write-observation-line! "slot-read-summary deliveries=%s edges=%s max-edges=%s"
        deliveries edges largest)
      (report-clos-roots)
      (report-reader-roots))))
