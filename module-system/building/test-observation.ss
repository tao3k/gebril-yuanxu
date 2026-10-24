;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module-specific adapter of the existing Case policy, never a runner.
(import :clan/poo/object
        (only-in :clan/poo/slot-observation call-with-slot-read-observer
                 slot-read-key slot-read-receiver slot-read-dependencies)
        (only-in :yuanxu/poo-clos/types ClosEffectiveMethod ClosInvocationFrame)
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander current-expander-compile current-expander-context
                 current-expander-phi module-context? module-context-path
                 module-context-code expander-context-table)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile
                 yuanxu-test-checkpoint yuanxu-test-observe)
        (only-in :yuanxu/observability/memory yuanxu-debug-cpu-microseconds)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 current-module-process-trace-budget))
(export ModuleTestingProfile.)

;; Stable owner/role labels distinguish many modules' func.ss and types.ss.
;; This is only formatting of an observed path: no scan, import or slot read.
(def observation-source-root
  (string-append
    (path-strip-trailing-directory-separator
      (path-normalize (path-expand "../.." (path-directory (this-source-file))))) "/"))
(def (source-label path)
  (if (string-prefix? observation-source-root path)
    (substring path (string-length observation-source-root) (string-length path))
    (path-strip-directory path)))

(def (module-test-observer previous trace?)
  (def started (current-jiffy))
  (def started-cpu (yuanxu-debug-cpu-microseconds))
  ;; Diagnostic counts only: bounded owner/phase rows, never source bytes,
  ;; SDK contexts or currentness results. This cannot authorize reuse.
  (def read-rows (and trace? (make-hash-table)))
  (def effect-reads (and trace? (make-hash-table)))
  (def physical-reads 0)
  (def public-requests 0)
  (def public-preparations 0)
  (def kernel-requests 0)
  (def kernel-walks 0)
  (def kernel-visits 0)
  (def effects '())
  (def guard-origins '())
  (def publications 0)
  (def replay-visits 0)
  (def (span-total key (cpu? #f))
    (let (span (find (lambda (span) (eq? key (caddr (vector-ref span 0)))) spans))
      (if span (vector-ref span (if cpu? 5 4)) 0)))
  (def (report-phase-work (force? #f))
    ;; Bounded checkpoints survive a later outer TERM without retaining a
    ;; token/context census or waiting for a successful Case's final receipt.
    (when (and trace? (or force? (zero? (modulo publications 64))))
      (yuanxu-write-observation-line!
        "reader-phase-wall publications=%s import-us=%s compile-us=%s eval-us=%s replay-us=%s replay-visits=%s guard-us=%s"
        publications (span-total 'import-microseconds)
        (span-total 'reader-compile-microseconds)
        (span-total 'reader-eval-microseconds)
        (span-total 'metadata-replay-microseconds)
        replay-visits
        (span-total 'source-guard-microseconds))
      (yuanxu-write-observation-line!
        "reader-phase-cpu publications=%s import-us=%s compile-us=%s eval-us=%s replay-us=%s guard-us=%s"
        publications (span-total 'import-microseconds #t)
        (span-total 'reader-compile-microseconds #t)
        (span-total 'reader-eval-microseconds #t)
        (span-total 'metadata-replay-microseconds #t)
        (span-total 'source-guard-microseconds #t))
      (for-each
        (lambda (keys)
          (yuanxu-write-observation-line!
            "reader-boundary publications=%s kind=%s wall-us=%s cpu-us=%s"
            publications (car keys) (span-total (cadr keys))
            (span-total (cadr keys) #t)))
        '((location reader-location-microseconds reader-location-cpu-microseconds)
          (preparation reader-preparation-microseconds reader-preparation-cpu-microseconds)
          (interface reader-interface-microseconds reader-interface-cpu-microseconds)
          (admission reader-admission-microseconds reader-admission-cpu-microseconds)
          (projection reader-projection-microseconds reader-projection-cpu-microseconds)))))
  (def (read-owner path)
    (let (parts (string-split (source-label path) #\/))
      (cond
        ((string-contains path "/clan/poo/") "gerbil-poo")
        ((and (member (car parts) '("modules" "module-system" "scenarios" "t"))
              (pair? (cdr parts)))
         (string-append (car parts) "/" (cadr parts)))
        (else (car parts)))))
  (def (record-read phase path amount)
    (when read-rows
      (set! physical-reads (+ physical-reads amount))
      (let* ((effect (if (pair? effects) (car effects) '(outside-effect . source)))
             (key (if (or (hash-key? effect-reads effect) (< (hash-length effect-reads) 128))
                    effect '(overflow . other))))
        (hash-put! effect-reads key (+ amount (or (hash-get effect-reads key) 0))))
      (let* ((row (list phase (if (pair? guard-origins) (car guard-origins) 'outside-guard)
                        (read-owner path)))
             (key (if (or (hash-key? read-rows row) (< (hash-length read-rows) 1024))
                    row '(overflow outside-guard "other"))))
        (hash-put! read-rows key (+ amount (or (hash-get read-rows key) 0))))))
  (def (flush-reads)
    (report-phase-work #t)
    (when trace?
      (yuanxu-write-observation-line!
        "public-source-preparation requests=%s preparations=%s"
        public-requests public-preparations)
      (yuanxu-write-observation-line!
        "kernel-source-closure requests=%s walks=%s visits=%s"
        kernel-requests kernel-walks kernel-visits))
    (when read-rows
      (for-each
        (lambda (row)
          (yuanxu-write-observation-line!
            "source-physical phase=%s boundary=%s owner=%s reads=%s"
            (caar row) (cadar row) (caddar row) (cdr row)))
        (hash->list read-rows)))
    (when effect-reads
      (for-each
        (lambda (row)
          (yuanxu-write-observation-line! "source-effect kind=%s boundary=%s reads=%s"
            (caar row) (cdar row) (cdr row)))
        (hash->list effect-reads))))
  ;; Closed categories, not a path/context registry. Nested imports/guards are
  ;; counted as a union of spans so recursive import edges do not multiply time.
  ;; Keep timing scalar even when this observer runs inside domain admission.
  (def spans
    (map (lambda (keys) (vector keys 0 0 0 0 0))
      '((native-source-import-start native-source-import-end
          import-microseconds import-cpu-microseconds)
        (publication-start publication-end
          publication-microseconds publication-cpu-microseconds)
        (publication-guard-start publication-guard-end
          source-guard-microseconds source-guard-cpu-microseconds)
        (metadata-replay-start metadata-replay-end
          metadata-replay-microseconds metadata-replay-cpu-microseconds)
        (reader-compile-start reader-compile-end
          reader-compile-microseconds reader-compile-cpu-microseconds)
        (reader-eval-start reader-eval-end
          reader-eval-microseconds reader-eval-cpu-microseconds)
        (reader-location-start reader-location-end
          reader-location-microseconds reader-location-cpu-microseconds)
        (reader-preparation-start reader-preparation-end
          reader-preparation-microseconds reader-preparation-cpu-microseconds)
        (reader-interface-start reader-interface-end
          reader-interface-microseconds reader-interface-cpu-microseconds)
        (reader-admission-start reader-admission-end
          reader-admission-microseconds reader-admission-cpu-microseconds)
        (reader-projection-start reader-projection-end
          reader-projection-microseconds reader-projection-cpu-microseconds)
        (package-process-start package-process-end
          package-microseconds package-cpu-microseconds))))
  (def (observe-span category)
    (for-each
      (lambda (span)
        (let ((keys (vector-ref span 0)) (depth (vector-ref span 1)))
          (cond
            ((eq? category (car keys))
             (when (zero? depth)
               (vector-set! span 2 (current-jiffy))
               (vector-set! span 3 (yuanxu-debug-cpu-microseconds)))
             (vector-set! span 1 (+ depth 1)))
            ((and (eq? category (cadr keys)) (> depth 0))
             (vector-set! span 1 (- depth 1))
             (when (= depth 1)
               (let ((wall (quotient (* (- (current-jiffy) (vector-ref span 2)) 1000000)
                                     (jiffies-per-second)))
                     (cpu (- (yuanxu-debug-cpu-microseconds) (vector-ref span 3))))
                 (vector-set! span 4 (+ wall (vector-ref span 4)))
                 (vector-set! span 5 (+ cpu (vector-ref span 5)))
                 ;; Internal diagnostic spans must not consume the Case's
                 ;; unchanged 64 DOMAIN-category allowance.
                 (when (memq (car keys) '(native-source-import-start publication-start
                                         publication-guard-start package-process-start))
                   (yuanxu-test-observe (caddr keys) wall)
                   (yuanxu-test-observe (cadddr keys) cpu))))))))
      spans))
  ;; Automatic events can occur INSIDE domain admission. Do not construct or
  ;; inspect telemetry POO objects there: their reads would enter its MOP
  ;; dependency graph. The Case watchdog still samples/enforces memory, and
  ;; explicit author checkpoints retain their full receipt API.
  (def (stage category name)
    (when trace?
      (yuanxu-write-observation-line!
        "test-stage %s/%s elapsed-ms=%s cpu-ms=%s source-reads=%s" category name
        (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second))
        (quotient (- (yuanxu-debug-cpu-microseconds) started-cpu) 1000)
        physical-reads)))
  (def (observe key amount)
    ;; Never retain SDK objects in compound discovery keys. Only their closed
    ;; event category contributes a counter; actual objects stay with the SDK.
    (let (category (if (pair? key) (car key) key))
      (when (symbol? category)
        (cond
          ((eq? category 'metadata-replay-visits)
           (set! replay-visits (+ replay-visits amount)))
          ((memq category '(metadata-replay-start metadata-replay-end
                            reader-compile-start reader-compile-end reader-eval-start reader-eval-end
                            reader-location-start reader-location-end
                            reader-preparation-start reader-preparation-end
                            reader-interface-start reader-interface-end
                            reader-admission-start reader-admission-end
                            reader-projection-start reader-projection-end))
           (void))
          ;; Fixed diagnostic scalars must not displace the Case's domain
          ;; work categories. The original observer still receives each event.
          ((memq category '(public-preparation-requests public-preparation-walks
                            kernel-closure-requests kernel-closure-walks kernel-context-visits
                            reader-binding-roots reader-read-roots compiler-enrollment))
           (unless (and (exact-integer? amount) (>= amount 0))
             (error "source preparation observation requires a natural count"))
           (case category
             ((public-preparation-requests) (set! public-requests (+ public-requests amount)))
             ((public-preparation-walks) (set! public-preparations (+ public-preparations amount)))
             ((kernel-closure-requests) (set! kernel-requests (+ kernel-requests amount)))
             ((kernel-closure-walks) (set! kernel-walks (+ kernel-walks amount)))
             ((kernel-context-visits) (set! kernel-visits (+ kernel-visits amount)))))
          ((eq? category 'check-seconds)
            (unless (and (real? amount) (<= 0 amount) (< amount +inf.0))
              (error "source check duration must be finite and nonnegative"))
            (yuanxu-test-observe 'check-microseconds
              (inexact->exact (round (* amount 1000000)))))
          (else (yuanxu-test-observe category amount))))
      (when (pair? key)
        ;; Innermost active effect brackets partition physical reads without
        ;; summing overlapping spans. Names are producer-owned scalar labels.
        (when trace?
          (case category
            ((package-stage-start admission-stage-start package-process-start native-source-import-start)
             (set! effects
               (cons (cons category
                       (if (eq? category 'native-source-import-start)
                         (read-owner (cadr key)) (cadr key))) effects)))
            ((package-stage-end admission-stage-end package-process-end native-source-import-end)
             (when (pair? effects) (set! effects (cdr effects))))))
        (when (memq category '(native-source-import-start native-source-import-end
                              publication-start publication-end
                              publication-guard-start publication-guard-end
                              metadata-replay-start metadata-replay-end
                              reader-compile-start reader-compile-end
                              reader-eval-start reader-eval-end
                              reader-location-start reader-location-end
                              reader-preparation-start reader-preparation-end
                              reader-interface-start reader-interface-end
                              reader-admission-start reader-admission-end
                              reader-projection-start reader-projection-end
                              package-process-start package-process-end))
          (observe-span category))
        (case category
          ((file-read)
           (record-read (cadr key) (caddr key) amount))
          ((publication-guard-start)
           (set! guard-origins (cons (cadr key) guard-origins))
           (stage category (cadr key)))
          ((publication-guard-end)
           (stage category (cadr key))
           (when (pair? guard-origins) (set! guard-origins (cdr guard-origins))))
          ((publication-start publication-end)
           (when (eq? category 'publication-end)
             (set! publications (+ publications 1))
             (report-phase-work))
           (stage category
             (path-strip-directory
               (path-strip-trailing-directory-separator (path-directory (cadr key))))))
          ((package-stage-start package-stage-end admission-stage-start admission-stage-end
            package-process-start package-process-end)
           (stage category (cadr key)))
          ((package-store-validity)
           (stage category (cadr key)))
          ((native-source-import-start native-source-import-end)
           (stage category (source-label (cadr key))))
          ((reader-retention reader-binding-roots reader-read-roots reader-lifetime reader-declaration package-process-observation)
           ;; Producers own these closed scalar rows; reject unexpected payloads
           ;; rather than print syntax or accidentally root a runtime object.
           (unless (and (list? (cdr key))
                        (andmap (lambda (row)
                                  (and (pair? row) (symbol? (car row))
                                       (exact-integer? (cdr row)) (>= (cdr row) 0)))
                                (cdr key)))
             (error "module test observation requires scalar fields" category))
           (when trace? (yuanxu-write-observation-line! "%s %s" category (cdr key)))
           (when (eq? category 'package-process-observation)
             (for-each (lambda (row) (yuanxu-test-observe (car row) (cdr row))) (cdr key)))
           (when (eq? category 'reader-declaration)
             (stage category 'body)))))
      (when previous (previous key amount))))
  (values observe flush-reads))

(def (observe-module-test run)
  (lambda (self description thunk)
    (if (.get self emit?)
      (let (trace? (.get self trace-enabled?))
        (defvalues (observer flush-reads)
          (module-test-observer (current-module-source-observer) trace?))
        (parameterize ((current-module-source-observer
                         observer)
                       ;; The first four calls cover construction's evaluation,
                       ;; store lookup, realization and first currentness check.
                       ;; No evaluator/debug dump for every repeated admission.
                       (current-module-process-trace-budget (and trace? (box 4))))
          (dynamic-wind void
            (lambda ()
              (run self description
                (if trace? (lambda () (observe-read-dependencies thunk)) thunk)))
            flush-reads)))
      (run self description thunk))))

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
          "reader-sdk-roots role=%s contexts=%s bindings=%s code-bodies=%s expanded=%s programs=%s"
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
              (let* ((effective (if (eq? kind 'poo-clos/effective-method) value
                                 (hash-get instance 'effective-method)))
                     (fields (and (object? effective) (object-%instance effective)))
                     (generic (and fields (hash-get fields 'generic)))
                     (metadata (and (object? generic) (object-%instance generic))))
                (when (and metadata
                           (eq? (hash-get metadata 'identity) 'module-authoring-admit)
                           (= (length args) 4))
                  (hash-put! authoring-interfaces (caddr args) #t)
                  (hash-put! authoring-datums (cadddr args) #t)))))
        (when (and instance (procedure? (hash-get instance 'next)))
          (set! continuations (+ continuations 1))))) clos-values)
    (yuanxu-write-observation-line!
      "reader-clos-roots publications=%s effective=%s frames=%s argument-refs=%s argument-lists=%s authoring-interfaces=%s authoring-datums=%s continuations=%s read-records=%s"
      publications effective frames arguments (hash-length argument-lists)
      (hash-length authoring-interfaces) (hash-length authoring-datums)
      continuations (hash-length clos-reads)))
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
    ;; user payloads, execute a checker, or follow SDK/weak-registry internals.
    (def births (make-hash-table-eq))
    (def birth-cells 0)
    (def (birth! read)
      (defvalues (_presented original _signed _snapshot _shape) (object-read-issuance read))
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
      "slot-issuer-storage records=%s closures=%s captured-cells=%s"
      (hash-length seen) (hash-length births) birth-cells))
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

(.def (ModuleTestingProfile. @ yuanxu-default-testing-case-profile)
  trace-enabled?: #f
  (.run => observe-module-test))
