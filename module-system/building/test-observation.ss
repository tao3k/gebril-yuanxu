;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module-specific adapter of the existing Case policy, never a runner.
(import :clan/poo/object
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile
                 poo-flow-test-checkpoint poo-flow-test-observe)
        (only-in :core/observability/memory poo-flow-debug-cpu-microseconds)
        (only-in :core/observability/output poo-flow-write-observation-line!)
        (only-in :core/module-system/source/admission current-module-source-observer
                 current-module-process-trace-budget))
(export ModuleTestingProfile.)

(def (module-test-observer previous trace?)
  (def started (current-jiffy))
  (def started-cpu (poo-flow-debug-cpu-microseconds))
  ;; Closed categories, not a path/context registry. Nested imports/guards are
  ;; counted as a union of spans so recursive import edges do not multiply time.
  ;; Keep timing scalar even when this observer runs inside domain admission.
  (def spans
    (map (lambda (keys) (vector keys 0 0 0))
      '((native-source-import-start native-source-import-end
          import-microseconds import-cpu-microseconds)
        (publication-start publication-end
          publication-microseconds publication-cpu-microseconds)
        (publication-guard-start publication-guard-end
          source-guard-microseconds source-guard-cpu-microseconds)
        (nix-process-start nix-process-end
          nix-microseconds nix-cpu-microseconds))))
  (def (observe-span category)
    (for-each
      (lambda (span)
        (let ((keys (vector-ref span 0)) (depth (vector-ref span 1)))
          (cond
            ((eq? category (car keys))
             (when (zero? depth)
               (vector-set! span 2 (current-jiffy))
               (vector-set! span 3 (poo-flow-debug-cpu-microseconds)))
             (vector-set! span 1 (+ depth 1)))
            ((and (eq? category (cadr keys)) (> depth 0))
             (vector-set! span 1 (- depth 1))
             (when (= depth 1)
               (poo-flow-test-observe (caddr keys)
                 (quotient (* (- (current-jiffy) (vector-ref span 2)) 1000000)
                           (jiffies-per-second)))
               (poo-flow-test-observe (cadddr keys)
                 (- (poo-flow-debug-cpu-microseconds) (vector-ref span 3))))))))
      spans))
  ;; Automatic events can occur INSIDE domain admission. Do not construct or
  ;; inspect telemetry POO objects there: their reads would enter its MOP
  ;; dependency graph. The Case watchdog still samples/enforces memory, and
  ;; explicit author checkpoints retain their full receipt API.
  (def (stage category name)
    (when trace?
      (poo-flow-write-observation-line!
        "test-stage %s/%s elapsed-ms=%s cpu-ms=%s" category name
        (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second))
        (quotient (- (poo-flow-debug-cpu-microseconds) started-cpu) 1000))))
  (lambda (key amount)
    ;; Never retain SDK objects in compound discovery keys. Only their closed
    ;; event category contributes a counter; actual objects stay with the SDK.
    (let (category (if (pair? key) (car key) key))
      (when (symbol? category)
        (if (eq? category 'check-seconds)
          (begin
            (unless (and (real? amount) (<= 0 amount) (< amount +inf.0))
              (error "source check duration must be finite and nonnegative"))
            (poo-flow-test-observe 'check-microseconds
              (inexact->exact (round (* amount 1000000)))))
          (poo-flow-test-observe category amount)))
      (when (pair? key)
        (when (memq category '(native-source-import-start native-source-import-end
                              publication-start publication-end
                              publication-guard-start publication-guard-end
                              nix-process-start nix-process-end))
          (observe-span category))
        (case category
          ((publication-start publication-end)
           (stage category
             (path-strip-directory
               (path-strip-trailing-directory-separator (path-directory (cadr key))))))
          ((package-stage-start package-stage-end admission-stage-start admission-stage-end
            nix-process-start nix-process-end publication-guard-start publication-guard-end)
           (stage category (cadr key)))
          ((nix-store-validity)
           (stage category (cadr key)))
          ((native-source-import-start native-source-import-end)
           (stage category (path-strip-directory (cadr key))))
          ((reader-retention reader-lifetime reader-declaration)
           ;; Producers own these closed scalar rows; reject unexpected payloads
           ;; rather than print syntax or accidentally root a runtime object.
           (unless (and (list? (cdr key))
                        (andmap (lambda (row)
                                  (and (pair? row) (symbol? (car row))
                                       (exact-integer? (cdr row)) (>= (cdr row) 0)))
                                (cdr key)))
             (error "module test observation requires scalar fields" category))
           (when trace? (poo-flow-write-observation-line! "%s %s" category (cdr key)))
           (when (eq? category 'reader-declaration)
             (stage category 'body)))))
      (when previous (previous key amount)))))

(def (observe-module-test run)
  (lambda (self description thunk)
    (if (.get self emit?)
      (let (trace? (.get self trace-enabled?))
        (parameterize ((current-module-source-observer
                         (module-test-observer (current-module-source-observer) trace?))
                       ;; The first four calls cover construction's evaluation,
                       ;; store lookup, realization and first currentness check.
                       ;; No evaluator/debug dump for every repeated admission.
                       (current-module-process-trace-budget (and trace? (box 4))))
          (run self description thunk)))
      (run self description thunk))))

(.def (ModuleTestingProfile. @ poo-flow-default-testing-case-profile)
  trace-enabled?: #f
  (.run => observe-module-test))
