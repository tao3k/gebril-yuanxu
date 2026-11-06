;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Assertion workloads called by the existing std/test Case in this process.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-checkpoint)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer module-source-read
                 call-with-module-source-operation-measurement)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads))
(export verify-declaration-scale verify-runtime-scale verify-runtime-selection verify-runtime-attribution
        verify-module-eval-once verify-business-eval-once
        verify-sparse-business-eval verify-sparse-business-attribution)

(def (verify-declaration-scale FixtureExports SelectedCount source-root)
  (def count (length (.all-slots (.get FixtureExports modules))))
  (check-equal? count SelectedCount)
  (def counts (make-hash-table-eq))
  ;; Bounded phase/family totals, never per-module paths or retained records.
  ;; Derive the boundary from the acquired fixture's actual source owner.
  (def source-prefix
    (path-normalize source-root))
  (def source-reads (make-hash-table))
  (def class-construction-reads 0)
  (def completed-declarations 0)
  (def previous (current-module-source-observer))
  (def (observe key amount)
    (def category (if (pair? key) (car key) key))
    (when (eq? category 'file-read)
      (let ((phase (if (memq (cadr key)
                            '(source publication-current declaration-before candidate-admitted
                              publication-inputs slot-replay return-currentness))
                    (cadr key) 'other))
            (family (if (string-prefix? source-prefix (caddr key)) 'module 'runtime)))
        (hash-update! source-reads (cons phase family) (cut + <> amount) 0)))
    (when (and (eq? category 'file-read)
               (string-suffix? "/poo-clos/classes.ss" (caddr key)))
      (set! class-construction-reads (+ class-construction-reads amount)))
    ;; This fixture imports only maintained Core/Gerbil libraries and its own roles.
    ;; Fail at an unexpected fallback rather than spending the full
    ;; thousand-entry budget proving the same wrong import classification.
    ;; A warm known import need not import new code. Completion of an
    ;; actual declaration still advances the Case's scalar progress frame.
    ;; Do not construct typed checkpoint receipts inside an active reader.
    (when (eq? category 'publication-end)
      (set! completed-declarations (+ completed-declarations amount))
      (execution-progress! '(declaration-completed) completed-declarations)
      ;; Scalar snapshots follow real completed publications, not a timer.
      ;; Do not force GC or construct POO diagnostics inside this observer.
      (when (zero? (modulo completed-declarations 100))
        (let (stats (##process-statistics))
          (displayln "DECLARATION-MEMORY completed=" completed-declarations
                     " heap=" (f64vector-ref stats 15)
                     " live=" (f64vector-ref stats 17)
                     " allocated=" (f64vector-ref stats 7))
          (force-output))))
    (when (eq? category 'candidate-open-boundary)
      ;; Scalar-only failure attribution: constructing a typed receipt here
      ;; would reenter the admission whose refusal we are diagnosing.
      (let (stats (##process-statistics))
        (displayln "DECLARATION-REFUSAL heap=" (f64vector-ref stats 15)
                   " live=" (f64vector-ref stats 17)
                   " allocated=" (f64vector-ref stats 7))
        (force-output))
      (error "closed runtime declaration crossed an unexpected open boundary" (cdr key)))
    (when (memq category '(publication-start publication-discovered candidate-local-guard candidate-open-guard
                          reader-declaration reader-body-expanded reader-body-evaluated
                          compiler-source-import-start publication-guard-run file-read))
      (hash-update! counts category (cut + <> amount) 0))
    (when previous (previous key amount)))
  (yuanxu-test-checkpoint 'runtime-graph-start)
  (def graph
    (parameterize ((current-module-source-observer observe))
      (.get FixtureExports tests selected-graph)))
  (yuanxu-test-checkpoint 'runtime-graph-ready)
  (check-equal? source-prefix (path-normalize (path-directory (.get graph init-source))))
  (yuanxu-write-observation-line! "declaration-source-reads modules=%s counts=%s"
    count (hash->list source-reads))
  (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
  (check-equal? (length (.get graph module-order)) count)
  (check-equal? (car (.get graph module-order)) 'module-0)
  (check-equal? (hash-ref counts 'publication-start) count)
  (check-equal? (hash-ref counts 'publication-discovered) count)
  ;; Deferred Type construction has its own before/after source checks.
  ;; Keep those additional guards; never reuse a preflight verdict.
  (check-equal? (hash-ref counts 'candidate-local-guard) (* 6 count))
  (check-equal? (hash-get counts 'candidate-open-guard) #f)
  ;; Prototype-only dispatch queries descriptor values; it must not import
  ;; or register the optional logical Class construction implementation.
  (check-equal? class-construction-reads 0)
  ;; Each interface retains all declaration snapshots. Closed selection
  ;; expands interface and real Types only; Config/Objects stay cold.
  ;; module-deferred-reader-test verifies both activate on actual access
  ;; and invalid Type descriptors still fail before scope linking.
  (check-equal? (hash-ref counts 'reader-declaration) (* 3 count))
  (check-equal? (hash-ref counts 'reader-body-expanded) (* 2 count))
  (check-equal? (hash-ref counts 'reader-body-evaluated) (* 2 count))
  (check-equal? (.ref/cached (.get FixtureExports modules) 'module-0) #f)
  ;; The delegated observer already recorded these events. Replaying the
  ;; assertion counters would double the published work totals.
  ;; The path is supplied by the actual Graph, never a guessed fixture root.
  (def path (.get graph init-source))
  (def original (module-source-read path))
  (def current! (.get graph admit-current))
  ;; Measure the normal live Graph. GC is an Observability measurement,
  ;; not cache invalidation: the same selected Graph remains reachable.
  (def held (yuanxu-debug-memory-snapshot 'graph-held collect?: #t))
  (yuanxu-write-observation-line!
    "reader-graph-live modules=%s live-bytes=%s" count (.get held live-bytes))
  (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
  (dynamic-wind
    (lambda ()
      (call-with-output-file (list path: path truncate: #t)
        (lambda (port) (display original port) (newline port))))
    (lambda ()
      (check-exception (current!)
        (lambda (exception)
          (and (Error? exception)
               (string=? (Error-message exception) "stale module scope generation")))))
    (lambda ()
      (call-with-output-file (list path: path truncate: #t) (cut display original <>))))
)

(def (measure-runtime count phase action)
  ;; Print actual phase entry, independently of detailed Profile emission.
  ;; These are actual work boundaries, never timer-generated progress.
  (yuanxu-write-observation-line! "runtime-capacity-start modules=%s phase=%s" count phase)
  (yuanxu-test-checkpoint phase)
  (def value #f)
  (def failed? #f)
  (def cause #f)
  (def stats
    (##exec-stats
      (lambda ()
        (with-catch
          (lambda (failure) (set! failed? #t) (set! cause failure))
          (lambda () (set! value (action)))))))
  (yuanxu-write-observation-line!
    "runtime-capacity modules=%s observer=absent phase=%s metrics=%s native-vm-account=%s vm-account-qualified?=false"
    count phase (filter (lambda (entry) (not (memq (car entry) '(result bytes-allocated)))) stats)
    (cdr (assq 'bytes-allocated stats)))
  (when failed?
    (yuanxu-write-observation-line! "runtime-phase-incomplete modules=%s phase=%s" count phase)
    (raise cause))
  value)

(def (verify-runtime-scale FixtureExports SelectedCount _source-root)
  (check-equal? (current-module-source-observer) #f)
  (def count SelectedCount)
  (measure-runtime count 'first-namespace
    (lambda () (check-equal? (length (.all-slots (.get FixtureExports modules))) count)))
  (check-equal? (.ref/cached (.get FixtureExports modules) 'module-1) #f)
  (def target (measure-runtime count 'first-scope (lambda () (.get FixtureExports modules module-1))))
  (def unrelated (.get FixtureExports modules module-2))
  (def untouched (.get unrelated plan))
  (def old-reads '())
  (def initial
    (measure-runtime count 'first-value
      (lambda ()
        (defvalues (value reads) (%call-with-recorded-slot-reads (cut .get target plan)))
        (set! old-reads reads)
        value)))
  (check-equal? initial '(5432))
  (def hot (measure-runtime count 'hot-value (lambda () (.get target plan))))
  (check-equal? (eq? hot initial) #t)
  (check-equal? (.call target computations) 1)
  (measure-runtime count 'change-config (lambda () (.put! (.get target config) 'port 5440)))
  (check-exception (replay-slot-reads! old-reads void) error?)
  (def changed (measure-runtime count 'incremental-value (lambda () (.get target plan))))
  (check-equal? changed '(5440))
  (check-equal? (.call target computations) 2)
  (check-equal? (eq? untouched (.get unrelated plan)) #t)
  (check-equal? (.call unrelated computations) 1)
  (check-equal? (.ref/cached target 'unselected) #f)
  (check-equal? (.ref/cached unrelated 'unselected) #f)
  (check-equal? (.ref/cached (.get FixtureExports modules) 'module-3) #f)
  (def demand (.get (.call (.get FixtureExports tests) .select '(module-1)) source))
  (check-equal? (.ref/cached demand 'selected-graph) #f)
  ;; Hot value access is not admission. Independently authenticate sources
  ;; after the edit; never report a cache hit as a fresh admission verdict.
  (measure-runtime count 'independent-currentness (lambda () ((.get demand admit-current))))
  (check-equal? (.ref/cached demand 'selected-graph) #f)
  (def memory (yuanxu-debug-memory-snapshot 'runtime-graph-held collect?: #t))
  (yuanxu-write-observation-line!
    "runtime-capacity-complete modules=%s recomputed=1 unrelated=0 unselected=cold live-bytes=%s"
    count (.get memory live-bytes))
)

(def (verify-runtime-selection FixtureExports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (measure-runtime count 'first-namespace
    (lambda () (check-equal? (length (.all-slots (.get FixtureExports modules))) count)))
  (def graph
    (measure-runtime count 'first-graph
      (lambda ()
        (defvalues (value times)
          (call-with-module-source-operation-measurement
            (lambda () (.get FixtureExports tests selected-graph))))
        (yuanxu-write-observation-line!
          "runtime-source-work modules=%s metrics=%s" count (hash->list times))
        value)))
  (check-equal? (length (.get graph module-order)) count)
  (check-equal? (.ref/cached (.get FixtureExports modules) 'module-1) #f)
  (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
  (measure-runtime count 'independent-currentness (lambda () ((.get graph admit-current)))))

;; Scalar-only attribution of the same real fixture. Preserve the original
;; exception (including raised #f) after reporting partial operation totals.
;; This installs no source observer and changes no Case or heap budget.
(def (measure-runtime-source count phase action (accounting? #f))
  (measure-runtime count phase
    (lambda ()
      (def failed? #f)
      (def cause #f)
      (defvalues (value times)
        (call-with-module-source-operation-measurement
          (lambda ()
            (with-catch
              (lambda (failure) (set! failed? #t) (set! cause failure) #f)
              action)) accounting?: accounting?))
      (yuanxu-write-observation-line!
        "runtime-phase-work modules=%s phase=%s failed?=%s metrics=%s"
        count phase failed? (hash->list times))
      (if failed? (raise cause) value))))
(def (verify-runtime-attribution FixtureExports count _source-root accounting?: (accounting? #f))
  (check-equal? (current-module-source-observer) #f)
  (def modules
    (measure-runtime count 'branch-construction
      (lambda () (.get FixtureExports modules))))
  (measure-runtime count 'branch-enumeration
    (lambda () (check-equal? (length (.all-slots modules)) count)))
  (def graph
    (measure-runtime-source count 'declaration-admission
      (lambda () (.get FixtureExports tests selected-graph)) accounting?))
  (check-equal? (length (.get graph module-order)) count)
  (check-equal? (.ref/cached modules 'module-1) #f)
  (measure-runtime-source count 'currentness-only (lambda () ((.get graph admit-current))) accounting?)
  (def target
    (measure-runtime-source count 'scope-after-admission
      (lambda () (.get FixtureExports modules module-1)) accounting?))
  (check-equal? (.get target plan) '(5432))
  (check-equal? (.ref/cached modules 'module-3) #f))

;; End-to-end call timing, without the per-read instrumentation overhead of the
;; attribution Case. An explicit expression identifies what this EVAL measures;
;; source currentness and scope construction are not silently included in hot .get.
(def (verify-module-eval-once FixtureExports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (def modules (.get FixtureExports modules))
  (def names (.all-slots modules))
  (check-equal? (length names) count)
  (yuanxu-write-observation-line!
    "eval-once-boundary modules=%s expression=%s operation-measurement=off"
    count '(.get FixtureExports tests selected-graph))
  (def graph
    (measure-runtime count 'eval-once-declarations
      (lambda () (.get FixtureExports tests selected-graph))))
  (check-equal? (length (.get graph module-order)) count)
  (for-each (lambda (id) (check-equal? (.ref/cached modules id) #f)) names)
  (def hot
    (measure-runtime count 'eval-again-same-expression
      (lambda () (.get FixtureExports tests selected-graph))))
  (check-equal? (eq? graph hot) #t)
  (measure-runtime count 'independent-currentness (lambda () ((.get graph admit-current))))
  (yuanxu-write-observation-line!
    "eval-once-complete modules=%s admitted=%s business-scopes=0 repeated-identity=ok"
    count (length (.get graph module-order))))

;; Confirmed main benchmark: one business .get, including its FIRST complete
;; declaration admission, reached scopes and returned value. Do not warm Graph.
(def (verify-business-eval-once FixtureExports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  ;; Inspect only the existing slot state. The timed expression owns first
  ;; branch construction as well as admission and scope demand.
  (check-equal? (.ref/cached FixtureExports 'modules) #f)
  (yuanxu-write-observation-line!
    "business-eval-boundary modules=%s expression=%s operation-measurement=off"
    count '(.get FixtureExports modules module-1 plan))
  (def cold
    (measure-runtime count 'business-eval-cold
      (lambda () (.get FixtureExports modules module-1 plan))))
  (check-equal? cold '(5432))
  (def hot
    (measure-runtime count 'business-eval-hot
      (lambda () (.get FixtureExports modules module-1 plan))))
  (check-equal? (eq? cold hot) #t)
  (def modules (.get FixtureExports modules))
  (check-equal? (length (.all-slots modules)) count)
  (check-equal? (.call (.get modules module-1) computations) 1)
  (for-each (lambda (id)
              (unless (memq id '(module-0 module-1))
                (check-equal? (.ref/cached modules id) #f)))
            (.all-slots modules))
  (def graph (.get FixtureExports tests selected-graph))
  (check-equal? (length (.get graph module-order)) count)
  (yuanxu-write-observation-line!
    "business-eval-complete modules=%s declarations=%s demanded=module-1 provider=module-0 unrelated=cold"
    count (length (.get graph module-order))))

(def (check-sparse-business-result exports count value)
  (check-equal? value '(5432))
  (def modules (.get exports modules))
  (def names (.all-slots modules))
  (check-equal? (length names) count)
  (check-equal? (.get exports tests selected-graph module-order) '(module-0 module-1))
  (for-each (lambda (id)
              (unless (memq id '(module-0 module-1))
                (check-equal? (.ref/cached modules id) #f)))
            names))

(def (verify-sparse-business-eval exports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (check-equal? (.ref/cached exports 'modules) #f)
  (def value (measure-runtime count 'sparse-business-cold
               (lambda () (.get exports modules module-1 plan))))
  (check-sparse-business-result exports count value)
  (yuanxu-write-observation-line! "sparse-business-ok catalog=%s roots=1 closure=2" count))

(def (verify-sparse-business-attribution exports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (measure-runtime count 'sparse-directory
    (lambda () (check-equal? (length (.all-slots (.get exports modules))) count)))
  (def (measured phase action)
    (measure-runtime count phase
      (lambda ()
        (call-with-values
          (lambda () (call-with-module-source-operation-measurement action accounting?: #f))
          cons))))
  (def (calls measured key) (hash-ref (cdr measured) (list 'calls key) 0))
  (def (admissions measured)
    (+ (calls measured 'candidate-read) (calls measured 'publication-read)))
  (def graph (measured 'sparse-admission (lambda () (.get exports tests selected-graph))))
  (check-equal? (.get (car graph) module-order) '(module-0 module-1))
  (check-equal? (admissions graph) 2)
  (check-equal? (calls graph 'scope-factory) 0)
  (def scope (measured 'sparse-scope-value (lambda () (.get exports modules module-1 plan))))
  (check-equal? (admissions scope) 0)
  (check-equal? (calls scope 'scope-factory) 2)
  (check-equal? (calls scope '(scope-factory module-0)) 1)
  (check-equal? (calls scope '(scope-factory module-1)) 1)
  (check-sparse-business-result exports count (car scope))
  (yuanxu-write-observation-line!
    "sparse-attribution-ok catalog=%s roots=1 admissions=2 scopes=2 owners=module-0,module-1" count))
