;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Assertion workloads called by the existing std/test Case in this process.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-checkpoint)
        (only-in :tao3k/yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :tao3k/yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :tao3k/yuanxu/module-system/source/admission current-module-source-observer module-source-read
                 call-with-module-source-operation-measurement)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads))
(export verify-declaration-scale verify-runtime-scale verify-runtime-selection verify-runtime-attribution
        verify-module-eval-once verify-business-eval-once
        verify-sparse-business-eval verify-sparse-business-attribution)

(def (verify-declaration-scale FixtureExports count source-root)
  (check-equal? (current-module-source-observer) #f)
  (def modules (.get FixtureExports modules))
  (def names (.all-slots modules))
  (check-equal? (length names) count)
  (def measured
    (measure-runtime count 'runtime-graph-start
      (lambda ()
        (call-with-values
          (lambda ()
            (call-with-module-source-operation-measurement
              (lambda () (.get FixtureExports tests selected-graph))
              accounting?: (cond-expand (yuanxu-module-test-stage-accounting 'stages)
                                         (else #f))))
          cons))))
  (def graph (car measured))
  (def counts (cdr measured))
  (def (calls operation) (hash-ref counts (list 'calls operation) 0))
  (yuanxu-test-checkpoint 'runtime-graph-ready)
  (check-equal? (path-normalize source-root) (path-normalize (path-directory (.get graph init-source))))
  (check-equal? (length (.get graph module-order)) count)
  (check-equal? (car (.get graph module-order)) 'module-0)
  (check-equal? (calls 'candidate-read) count)
  (check-equal? (calls 'publication-read) 0)
  (check-equal? (calls 'reader-candidate-fused-return-replay) count)
  (check-equal? (calls 'reader-wrapper-expansion) count)
  ;; Only the Interface and Types initialize. The focused deferred-reader
  ;; tests exercise the open observer, cold Config/Objects and invalid Types.
  (check-equal? (calls 'reader-compile-start) (* 2 count))
  (check-equal? (calls 'reader-eval-start) (* 2 count))
  (check-equal? (calls 'scope-factory) 0)
  (for-each (lambda (id) (check-equal? (.ref/cached modules id) #f)) names)
  (yuanxu-write-observation-line!
    "declaration-source modules=%s wrappers=%s initializers=%s metadata-replay-visits=%s"
    count (calls 'reader-wrapper-expansion) (calls 'reader-eval-start)
    (hash-ref counts '(visits metadata-replay) 0))
  ;; Resolve the exact init through the selected Graph before testing a
  ;; separate currentness refusal against that same Graph.
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

(def (measure-runtime count phase action observer: (observer 'absent))
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
    "runtime-capacity modules=%s observer=%s phase=%s metrics=%s build-vm-account=%s vm-account-qualified?=false"
    count observer phase (filter (lambda (entry) (not (memq (car entry) '(result bytes-allocated)))) stats)
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
  (def target
    (measure-runtime count 'first-scope
      (lambda ()
        (defvalues (scope times)
          (call-with-module-source-operation-measurement
            (lambda () (.get FixtureExports modules module-1)) accounting?: #f))
        (check-equal? (hash-ref times '(calls candidate-read) 0) 2)
        (check-equal? (hash-ref times '(calls (scope-factory module-0)) 0) 1)
        (check-equal? (hash-ref times '(calls (scope-factory module-1)) 0) 1)
        (check-equal? (hash-ref times '(calls scope-factory) 0) 2)
        scope)))
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
  (def demand
    (measure-runtime count 'select-currentness-demand
      (lambda () (.get (.call (.get FixtureExports tests) .select '(module-1)) source))))
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
  (def (measure-selection phase action)
    (cond-expand
      (yuanxu-module-test-stage-accounting
        (measure-runtime-source count phase action 'stages))
      (else (measure-runtime count phase action))))
  (measure-runtime count 'first-namespace
    (lambda () (check-equal? (length (.all-slots (.get FixtureExports modules))) count)))
  (def graph
    (measure-selection 'first-graph
      (lambda () (.get FixtureExports tests selected-graph))))
  (check-equal? (length (.get graph module-order)) count)
  (check-equal? (.ref/cached (.get FixtureExports modules) 'module-1) #f)
  (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
  (measure-selection 'independent-currentness (lambda () ((.get graph admit-current)))))

;; Scalar-only attribution of the same real fixture. Preserve the original
;; exception (including raised #f) after reporting partial operation totals.
;; This adds no source observer of its own and changes no Case or heap budget.
(def (measure-runtime-source count phase action (accounting? #f) observer: (observer 'absent))
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
      (if failed? (raise cause) value))
    observer: observer))
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

;; The first business .get admits its reached closure in a cold namespace.
;; Full-directory certification is a separate demand after both business reads.
(def (verify-business-eval-once FixtureExports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  ;; Inspect only the existing slot state. The timed expression owns first
  ;; branch construction as well as admission and scope demand.
  (check-equal? (.ref/cached FixtureExports 'modules) #f)
  (yuanxu-write-observation-line!
    "business-eval-boundary modules=%s expression=%s operation-accounting=scalar"
    count '(.get FixtureExports modules module-1 plan))
  (def (business-phase phase)
    (measure-runtime count phase
      (lambda ()
        (call-with-values
          (lambda ()
            (call-with-module-source-operation-measurement
              (lambda () (.get FixtureExports modules module-1 plan)) accounting?: #f))
          cons))))
  (def (calls run operation) (hash-ref (cdr run) (list 'calls operation) 0))
  (def (admissions run) (+ (calls run 'candidate-read) (calls run 'publication-read)))
  (def cold-run (business-phase 'business-eval-cold))
  (def cold (car cold-run))
  (check-equal? cold '(5432))
  (check-equal? (admissions cold-run) 2)
  (check-equal? (calls cold-run 'scope-factory) 2)
  (check-equal? (calls cold-run '(scope-factory module-0)) 1)
  (check-equal? (calls cold-run '(scope-factory module-1)) 1)
  (def hot-run (business-phase 'business-eval-hot))
  (check-equal? (eq? cold (car hot-run)) #t)
  (check-equal? (admissions hot-run) 0)
  (check-equal? (calls hot-run 'scope-factory) 0)
  (def modules (.get FixtureExports modules))
  (check-equal? (length (.all-slots modules)) count)
  (check-equal? (.call (.get modules module-1) computations) 1)
  (for-each (lambda (id)
              (unless (memq id '(module-0 module-1))
                (check-equal? (.ref/cached modules id) #f)))
            (.all-slots modules))
  (yuanxu-write-observation-line!
    "business-eval-complete modules=%s admissions=2 scopes=2 demanded=module-1 provider=module-0 unrelated=cold"
    count)
  (def graph
    (cond-expand
      (yuanxu-module-test-stage-accounting
        (measure-runtime-source count 'full-graph-after-business
          (lambda () (.get FixtureExports tests selected-graph)) 'stages))
      (else
        (measure-runtime count 'full-graph-after-business
          (lambda () (.get FixtureExports tests selected-graph))))))
  (check-equal? (length (.get graph module-order)) count)
  (yuanxu-write-observation-line!
    "business-eval-full-graph modules=%s declarations=%s" count (length (.get graph module-order))))

(def (check-sparse-business-result exports value)
  (check-equal? value '(5432))
  (def modules (.get exports modules))
  (check-equal? (.all-slots modules) '(module-1))
  (check-equal? (.get exports tests selected-graph module-order) '(module-0 module-1)))

(def (verify-sparse-business-eval exports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (check-equal? (.ref/cached exports 'modules) #f)
  (def run
    (measure-runtime count 'sparse-business-cold
      (lambda ()
        (call-with-values
          (lambda ()
            (call-with-module-source-operation-measurement
              (lambda () (.get exports modules module-1 plan)) accounting?: #f))
          cons))))
  (def work (cdr run))
  (check-equal? (hash-ref work '(calls candidate-read) 0) 2)
  (check-equal? (hash-ref work '(calls scope-factory) 0) 2)
  (check-equal? (hash-ref work '(calls (scope-factory module-0)) 0) 1)
  (check-equal? (hash-ref work '(calls (scope-factory module-1)) 0) 1)
  (check-sparse-business-result exports (car run))
  (yuanxu-write-observation-line! "sparse-business-ok catalog=%s roots=1 closure=2" count))

(def (verify-sparse-business-attribution exports count _source-root)
  (check-equal? (current-module-source-observer) #f)
  (measure-runtime count 'sparse-directory
    (lambda () (check-equal? (.all-slots (.get exports modules)) '(module-1))))
  (def (measured phase action)
    (measure-runtime count phase
      (lambda ()
        (defvalues (value work)
          (call-with-module-source-operation-measurement action
            accounting?: (cond-expand (yuanxu-module-test-stage-accounting 'stages)
                                       (else #f))))
        (cond-expand
          (yuanxu-module-test-stage-accounting
            (def (report stage)
              (yuanxu-write-observation-line!
                "sparse-stage modules=%s phase=%s stage=%s calls=%s wall=%s cpu=%s"
                count phase stage (hash-ref work (list 'calls stage) 0)
                (hash-ref work stage 0.)
                (+ (hash-ref work (list 'cpu-user stage) 0.)
                   (hash-ref work (list 'cpu-system stage) 0.))))
            (for-each
              report
              '(profile-interface-scan directory-current-observations link-current
                reader-wrapper-expansion reader-admission-start metadata-replay scope-factory))
            (for-each report
              (filter (lambda (stage)
                        (and (pair? stage) (memq (car stage) '(link-current scope-current))))
                      (hash-keys work))))
          (else (void)))
        (cons value work))))
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
  (check-sparse-business-result exports (car scope))
  (def hot (measured 'sparse-business-hot (lambda () (.get exports modules module-1 plan))))
  (check-equal? (eq? (car hot) (car scope)) #t)
  (check-equal? (admissions hot) 0)
  (check-equal? (calls hot 'scope-factory) 0)
  (yuanxu-write-observation-line!
    "sparse-attribution-ok catalog=%s roots=1 admissions=2 scopes=2 owners=module-0,module-1" count))
