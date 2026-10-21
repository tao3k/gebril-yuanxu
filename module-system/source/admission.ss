;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Shared source-role and publication admission. No expansion or activation.
(import (only-in :clan/poo/object .o .ref .ref/cached object? object-%instance object-protocol
                 object-revision object-supers)
        (only-in :clan/poo/slot-observation %slot-read-active?)
        (only-in :core/module-system/source/role-forms poo-flow-module-allowed-entrypoint-roles)
        (only-in :std/list/list any)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        :core/module-system/source/objects
        :core/module-system/source/publication
        (only-in :core/module-system/source/interface poo-flow-module-interface)
        (only-in :core/module-system/authoring/import-policy
                 SourceInspectionPolicy. poo-flow-module-owner-import-datum-observations)
        (only-in :core/module-system/authoring/admission
                 call-with-module-authoring-read-scope
                 poo-flow-module-authoring-admit-datums
                 poo-flow-module-authoring-admission-accepted?
                 poo-flow-module-authoring-admission-diagnostics)
        (only-in :core/module-system/authoring/roles make-default-module-authoring-profile))
(export poo-flow-module-required-role-files poo-flow-module-allowed-entrypoint-roles
        poo-flow-module-style-policy-prototype poo-flow-default-module-style-policy
        module-source-type module-source-read module-source-name? module-source-admit-current!
        call-with-module-source-read-cache call-with-module-source-fresh-reads
        call-with-collected-module-sources
        module-source-observe current-module-source-observer current-module-source-phase
        current-module-process-trace-budget
        module-source-checked-operation module-source-operation-procedure
        module-source-operation-resume module-source-object-policy
        admit-module-value! admit-module-publication! module-source-style-policy-current?
        module-source-publication-policy)

;; Read-only native identity/revision support for parser-owned metadata. This
;; is not a currentness-result cache: every call compares the actual revisions
;; of every captured receiver/ancestor. Closed metadata rejects native MOP;
;; a general source identity snapshot can preserve an existing opaque protocol
;; without certifying its execution as pure.
(def (module-source-object-policy roots reject-protocols?: (reject-protocols? #t))
  (def seen (make-hash-table-eq))
  (def entries '())
  (def (visit value)
    (unless (hash-key? seen value)
      (hash-put! seen value #t)
      (set! entries (cons (cons value (object-revision value)) entries))
      (for-each visit (object-supers value))))
  (for-each visit roots)
  (source-object-policy entries reject-protocols?))
(def (source-object-policy entries reject-protocols?)
  ;; Construct outside the capture frame; do not retain its traversal table.
  (lambda ()
    (andmap (lambda (entry)
              (and (= (cdr entry) (object-revision (car entry)))
                   (or (not reject-protocols?)
                       (not (object-protocol (car entry)))))) entries)))

(def poo-flow-module-required-role-files '("types.ss" "objects.ss" "config.ss" "interface.ss"))

;; Structural decomposition of ONE operation, not a source approval or cache.
;; Only this constructor creates the paired entry/resume procedures. Neither
;; procedure retains a check result; every invocation still runs the tail guard.
(defstruct source-checked-operation (guard invoke resume) final: #t)
(def (module-source-checked-operation guard action)
  (unless (and (procedure? guard) (procedure? action))
    (error "source operation requires a guard and an action"))
  (def (resume) (action) (guard))
  (make-source-checked-operation guard (lambda () (guard) (resume)) resume))
(def (module-source-operation-procedure operation)
  (source-checked-operation-invoke operation))
(def (module-source-operation-resume receiver guard)
  ;; Inspect ONLY an already prepared ordinary native receiver, without a MOP
  ;; hook or read observer. Cold/mutated objects, overridden methods, different
  ;; guards and instrumented reads retain the ordinary checked call. This probe
  ;; must not execute anything between the caller's guard and the continuation.
  (and (object? receiver) (object-%instance receiver)
       (not (%slot-read-active?)) (not (object-protocol receiver))
       (let ((operation (.ref/cached receiver '%source-operation (lambda () #f)))
             (invoke (.ref/cached receiver 'admit-current (lambda () #f))))
         (and (source-checked-operation? operation)
              (eq? guard (source-checked-operation-guard operation))
              (eq? invoke (source-checked-operation-invoke operation))
              (source-checked-operation-resume operation)))))

(def (module-source-name? name)
  (and (string? name) (> (string-length name) 0)
       (not (member name '("." "..")))
       (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list name))))

(def current-module-source-observer (make-parameter #f))
;; A Case-owned logging allowance, never a query/currentness cache. The testing
;; adapter binds a fresh box only for detailed observation; execution consumes
;; it solely to add the provider's diagnostic flags to a bounded set of calls.
(def current-module-process-trace-budget (make-parameter #f))
;; Observer keys remain numeric counters: symbols for totals, or
;; (file-request/file-read phase path) for attribution. No observer, no path keys.
(def current-module-source-phase (make-parameter 'source))
(def (observe-source kind (amount 1))
  (when (current-module-source-observer)
    ((current-module-source-observer) kind amount)))
(def (module-source-type path)
  (module-source-observe read-module-source-type path))
(def (read-module-source-type path)
  (observe-source 'stats)
  (with-catch (lambda (_exception) #f)
              (lambda () (file-info-type (file-info path #f)))))
;; A reader validation is synchronous and effect-free. Reuse bytes and file-kind
;; observations only inside that boundary; every read requires regular-file
;; status. No cache survives an effect or an independent currentness call.
(def source-read-cache (make-parameter #f))
;; Pure-query reuse must also preserve enrollment in an enclosing admission.
;; Each nested collector is a distinct demand even when bytes are unchanged.
(def source-collectors (make-parameter '()))
(def (call-with-module-source-fresh-reads thunk)
  ;; Admission is an authority boundary even when a caller has an outer pure
  ;; observation window. Restore that window afterwards; never inherit its bytes.
  (parameterize ((source-read-cache #f)) (thunk)))
(def (call-with-module-source-read-cache thunk)
  (observe-source 'checks)
  ;; Requests include nested guards. Count actual fresh observation windows
  ;; separately so attribution cannot mistake cache hits for filesystem passes.
  (unless (source-read-cache) (observe-source 'read-windows))
  ;; Nested pure source guards share the outer validation's observations. The
  ;; owner MUST end this scope before expansion, writes or external effects.
  (cond
   ((source-read-cache) (thunk))
   ((not (current-module-source-observer))
    (parameterize ((source-read-cache (make-hash-table))) (thunk)))
   (else
    (let (started (real-time))
      (dynamic-wind void
        (lambda () (parameterize ((source-read-cache (make-hash-table))) (thunk)))
        (lambda () (observe-source 'check-seconds (- (real-time) started))))))))
(def (module-source-observe query . arguments)
  ;; Pure observations only, within the same validation boundary as file bytes.
  (let (cache (source-read-cache))
    (if cache
      ;; File-kind lookup has no collector enrollment. Share that physical
      ;; query across collectors in this same pure window; byte guards and
      ;; arbitrary queries still rerun for each collector and enroll normally.
      (let (key (cons query (cons (if (eq? query read-module-source-type)
                                   '() (source-collectors)) arguments)))
        (if (hash-key? cache key)
          (begin (observe-source 'query-hits) (hash-ref cache key))
          (let (value (apply query arguments))
            (observe-source 'query-misses)
            (hash-put! cache key value) value)))
      (apply query arguments))))
(def (observe-read-request path)
  (observe-source 'read-requests)
  (when (current-module-source-observer)
    (observe-source (list 'file-request (current-module-source-phase) path))))
(def (observe-read path)
  (observe-source 'reads)
  (when (current-module-source-observer)
    (observe-source (list 'file-read (current-module-source-phase) path))))
(def (module-source-read path)
  (observe-read-request path)
  (unless (eq? (module-source-type path) 'regular)
    (error "module role must be a regular file" path))
  (let (cache (source-read-cache))
    (if (and cache (hash-key? cache path)) (hash-ref cache path)
      (let (text (begin (observe-read path)
                       (call-with-input-file path read-all-as-string)))
        (when cache (hash-put! cache path text))
        text))))

;; Private per-admission observations; neither a field table nor a global log.
(defstruct source-observation (input message) final: #t)
(def (check-source-current! entry message)
  ;; Keep comparison reuse inside the EXISTING pure read window. Index by path,
  ;; then expected-text identity: hashing complete source texts on every hit
  ;; would replace a linear comparison with another linear operation. Distinct
  ;; expected revisions (including equal copies) must be checked independently.
  ;; Windows already require stable bytes/inputs; callbacks must end them.
  (def cache (source-read-cache))
  (def key (and cache (cons check-source-current! (car entry))))
  (def checked (and cache (hash-get cache key)))
  (if (and checked (hash-key? checked (cdr entry)))
    (observe-source 'source-comparison-hits)
    (begin
      (observe-source 'source-comparisons)
      (unless (if (cdr entry)
                (and (eq? (module-source-type (car entry)) 'regular)
                     (equal? (cdr entry) (module-source-read (car entry))))
                (not (module-source-type (car entry))))
        (error message (car entry)))
      ;; A failed check never enrolls a comparison result. Observation collection
      ;; remains in module-source-admit-current!, outside this memoized work.
      (when cache
        (unless checked
          (set! checked (make-hash-table-eq))
          (hash-put! cache key checked))
        (hash-put! checked (cdr entry) #t)))))
(def (call-with-collected-module-sources consume)
  (def by-path (make-hash-table))
  (def observed '())
  (def (collect! entry message)
    (def previous (or (hash-get by-path (car entry)) '()))
    ;; De-duplicate matching revisions without hashing whole source texts or
    ;; replacing an earlier revision of the same path with a later one.
    (unless (any (lambda (item)
                   (equal? (cdr (source-observation-input item)) (cdr entry))) previous)
      (let* ((input (cons (string-copy (car entry))
                         (and (cdr entry) (string-copy (cdr entry)))))
             (item (make-source-observation input message)))
        (hash-put! by-path (car input) (cons item previous))
        (set! observed (cons item observed)))))
  (def (current!)
    ;; No candidate traversal, and no re-reporting a replay into an outer scope.
    ;; Only actual admission checks enroll observations, not this final pass.
    (call-with-module-source-fresh-reads
      (lambda ()
        ;; The replay itself only checks retained observations. Start with
        ;; fresh bytes, then share physical reads within this one pure pass.
        ;; Never inherit an enclosing admission's pre-effect observations.
        (call-with-module-source-read-cache
          (lambda ()
            (for-each
              (lambda (item)
                (check-source-current! (source-observation-input item)
                                      (source-observation-message item)))
              (reverse observed)))))))
  (parameterize ((source-collectors (cons collect! (source-collectors))))
    (consume current!)))
(def (module-source-admit-current! observations
        (message "stale selected build input; regenerate the build entry"))
  ;; One authority for JSON, native slot sources and publication guards. Nested
  ;; admission contributes observations to every active enclosing scope.
  (for-each
    (lambda (entry)
      (check-source-current! entry message)
      (for-each (lambda (collect!) (collect! entry message)) (source-collectors)))
    observations))

(def (poo-flow-module-role-reference? datum module-name role)
  (let ((leaf (string-append role ".ss"))
        (relative (string-append "./" role))
        (suffix (string-append "/" (if (symbol? module-name) (symbol->string module-name) module-name) "/" role)))
    (cond
     ((symbol? datum)
      (let (reference (symbol->string datum))
        (or (string=? reference relative)
            (string-suffix? suffix reference))))
     ((string? datum)
      (or (string=? datum leaf) (string-suffix? suffix datum)))
     ((pair? datum)
      (or (poo-flow-module-role-reference? (car datum) module-name role)
          (poo-flow-module-role-reference? (cdr datum) module-name role)))
     ((vector? datum)
      (poo-flow-module-role-reference? (vector->list datum) module-name role))
     (else #f))))

(def (poo-flow-module-top-form-references-role? datums head module-name role)
  (and (any (lambda (form)
              (and (pair? form)
                   (eq? (car form) head)
                   (poo-flow-module-role-reference?
                    (cdr form) module-name role)))
            datums)
       #t))

(def (poo-flow-module-dependency-direction-validate! module-name module-root read-datums)
  (let ((layers '((types objects func config interface build)
                  (func objects config interface build)
                  (objects config interface build)
                  (config interface build)
                  (interface build))))
    (for-each
     (lambda (layer)
       (let* ((source-role (car layer))
              (path (path-expand
                     (string-append (symbol->string source-role) ".ss")
                     module-root)))
         (when (read-datums path)
           (let (datums (read-datums path))
             (for-each
              (lambda (forbidden-role)
                (when (poo-flow-module-top-form-references-role?
                       datums 'import module-name
                       (symbol->string forbidden-role))
                  (error "POO-FLOW-MODULE-E007 reversed module role dependency"
                         module-name source-role forbidden-role)))
              (cdr layer))))))
     layers)))

;;; The loader applies the Interface-owned authoring Profile to each stable
;;; role before exposing any entrypoint.  Admission reads inert datums only;
;;; it neither expands nor evaluates module source.
(def (poo-flow-module-role-authoring-validate! policy module-name module-root reader read-datums)
  ;; Interface creation validates the authoring Profile and its child roles.
  ;; Their temporary evidence belongs to the SAME region as datum dispatch.
  (call-with-module-authoring-read-scope
    (lambda ()
      (let* ((authoring (.ref policy 'authoring))
             (interface
              (poo-flow-module-interface
                (if (symbol? module-name) (symbol->string module-name) module-name) (.o)
                (list (cons 'module-root module-root))
                authoring: authoring)))
        (for-each
          (lambda (role)
            (let* ((path
                    (path-expand (string-append (symbol->string role) ".ss") module-root))
                   (admission
                    (poo-flow-module-authoring-admit-datums
                      interface (if (eq? role 'func) 'funs role) (read-datums path))))
              (unless (poo-flow-module-authoring-admission-accepted? admission)
                (error "POO-FLOW-MODULE-E009 role violates Interface authoring Contract"
                       module-name role path
                       (car (poo-flow-module-authoring-admission-diagnostics admission))))))
          (filter
            (lambda (role)
              (reader (path-expand (string-append (symbol->string role) ".ss") module-root) #f))
            '(types objects func config interface build)))))))


(def (poo-flow-module-source-admit! policy module-name module-root reader)
  (unless (eq? (module-source-type module-root) 'directory)
    (error "module source must be a directory" module-name module-root))
  (when (file-exists? (path-expand "init.ss" module-root))
    (error "POO-FLOW-MODULE-E005 init.ss belongs to the selection root" module-name))
  ;; Read each selected role once. The caller may record these exact bytes in
  ;; its generation; all checks consume the same inert source snapshot.
  (let ((texts (make-hash-table)) (parsed (make-hash-table)))
    (for-each
     (lambda (role)
       (let* ((path (path-expand (string-append (symbol->string role) ".ss") module-root))
              (required? (memq role '(types objects config interface))))
         (when (or required? (module-source-type path))
           (unless (eq? (module-source-type path) 'regular)
             (error "module role must be a regular file" module-name role path))
           (let* ((text (reader path))
                  (datums (call-with-input-string text read-all)))
             (observe-source 'role-parses)
             (unless (pair? datums)
               (error "module role cannot be empty" module-name role path))
             (hash-put! texts path text)
             (hash-put! parsed path datums)))))
     poo-flow-module-allowed-entrypoint-roles)
    (def (read-role path (required? #t))
      (if (hash-key? texts path) (hash-ref texts path)
        (if required? (error "source role was not admitted" path) #f)))
    (def (read-datums path) (hash-get parsed path))
    ;; One private parse per role/policy invocation. Structural checks and the
    ;; authoring protocol inspect the SAME source datums. Discard this snapshot
    ;; after the call; re-read/reparse and re-dispatch on the next invocation.
    (poo-flow-module-dependency-direction-validate!
     (path-strip-directory (path-strip-trailing-directory-separator module-root)) module-root read-datums)
    (hash-for-each
     (lambda (path text)
       (for-each
        (lambda (datum)
          (let (findings (poo-flow-module-owner-import-datum-observations
                           (string->symbol path) datum (.ref policy 'source-policy)))
            (when (pair? findings)
              (error "POO-FLOW-MODULE-E008 module owner imports aggregate facade"
                     module-name path (car findings)))))
        (read-datums path))) texts)
    (poo-flow-module-role-authoring-validate! policy module-name module-root read-role read-datums))
  module-root)

(def poo-flow-module-style-policy-prototype
  (.o (module-style-policy? #t)
      ;; Construct here, validate at make-module-interface. Validation inside
      ;; this computed default would retain its constructor receipts in every
      ;; later replay of the shared policy slot. Derived receivers still get
      ;; fresh defaults; this is not a shared accepted-Profile cache.
      (authoring (make-default-module-authoring-profile))
      source-policy: SourceInspectionPolicy.
      validate: poo-flow-module-source-admit!))
(def poo-flow-default-module-style-policy
  (.o (:: @ poo-flow-module-style-policy-prototype)))

;; Capture the maintained policy BEFORE exposing it for extension. Include its
;; actual Profile children; changing a role need not edit the containing slot.
(def (module-source-style-policy-support)
  (let* ((policy poo-flow-default-module-style-policy)
         (profile (.ref policy 'authoring)))
    (append (list policy profile (.ref policy 'source-policy))
        (filter object?
          (map (cut .ref profile <>) '(executor types objects funs config interface build))))))
(def default-style-policy-current
  (module-source-object-policy (module-source-style-policy-support)))
(def (module-source-style-policy-current?) (default-style-policy-current))
(def (module-source-publication-policy)
  ;; Snapshot the actual policy/Contract references before role execution.
  ;; Native initializer scratch reads are not admission requirements.
  (module-source-object-policy
    (cons ModulePublicationContract (module-source-style-policy-support))
    reject-protocols?: #f))

(def (admit-module-value! contract candidate context-value)
  (let (evidence (poo-flow-contract-admit contract candidate context-value))
    (unless (poo-flow-validation-evidence-accepted? evidence)
      (error "module scope admission refused" (.ref contract 'identity) evidence))
    evidence))
(def (admit-module-publication! source expected-id publication context-value)
  (unless (poo-flow-module-source-ref? source)
    (error "module publication requires a SourceRef" expected-id source))
  (let* ((evidence (admit-module-value! ModulePublicationContract publication context-value))
         ;; The public value Contract may return a different checked receiver.
         ;; Owner checks must describe THAT subject, not the pre-check input.
         (checked (.ref evidence 'candidate))
         (owner (assq 'module-id (poo-flow-module-source-ref-metadata source))))
    (unless (and (eq? expected-id (.ref checked 'identity))
                 (or (not owner) (eq? expected-id (cdr owner))))
      (error "publication source owner mismatch" expected-id source))
    evidence))
