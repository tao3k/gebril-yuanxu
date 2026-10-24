;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Existing Observability memory policies and Case watchdog, isolated from
;;; optional typed printers and slot tracing. No separate runner or sampler.
(import (only-in :clan/poo/object .o .ref)
        (only-in :yuanxu/ops/progress current-execution-progress execution-progress-status
                 execution-progress-idle-milliseconds execution-progress-limit)
        (only-in :clan/poo/mop validate)
        :gerbil/runtime/gambit
        (only-in :std/error deferror-class)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/types
                 YuanxuDebugMemoryPolicyContract YuanxuDebugMemorySampleContract
                 YuanxuDebugMemoryReceiptContract YuanxuDebugDurationReceiptContract)
        (only-in :yuanxu/observability/funcs
                 yuanxu-debug-memory-policy yuanxu-debug-memory-policy?
                 yuanxu-debug-memory-sample yuanxu-debug-memory-receipt
                 yuanxu-debug-memory-receipt-sexp yuanxu-debug-allocation-current?))
(export YuanxuDebugMemoryAnomaly? YuanxuDebugMemoryAnomaly-receipt
        YuanxuDebugDurationAnomaly? YuanxuDebugDurationAnomaly-receipt
        YuanxuDebugMemoryPolicyContract YuanxuDebugMemorySampleContract
        YuanxuDebugMemoryReceiptContract YuanxuDebugDurationReceiptContract
        yuanxu-debug-memory-policy yuanxu-debug-memory-policy?
        yuanxu-debug-memory-sample yuanxu-debug-memory-receipt
        yuanxu-debug-memory-receipt-sexp yuanxu-debug-memory-snapshot
        yuanxu-debug-allocation-current?
        yuanxu-debug-cpu-microseconds
        yuanxu-debug-memory-checkpoint call-with-yuanxu-debug-memory-span
        call-with-yuanxu-debug-memory-monitor call-with-yuanxu-debug-memory-case-watchdog)
(deferror-class YuanxuDebugMemoryAnomaly (receipt))
(deferror-class YuanxuDebugDurationAnomaly (receipt))
;; Scalar stop data is private. Raise the original public condition immediately;
;; populate its typed receipt only after the interrupted read scopes unwind.
(defstruct case-stop (failure kind data) final: #t)
(def DebugDurationReceipt. (.ref YuanxuDebugDurationReceiptContract 'proto))
(def (yuanxu-debug-cpu-microseconds)
  ;; Process CPU is distinct from elapsed wall time and from last-GC memory.
  ;; Use the SDK clock directly; no sampler, environment probe or subprocess.
  (let (times (##process-times))
    (inexact->exact
      (round (* 1000000 (+ (f64vector-ref times 0) (f64vector-ref times 1)))))))
(def (yuanxu-debug-elapsed-milliseconds started-jiffy)
  (quotient (* (- (current-jiffy) started-jiffy) 1000)
            (jiffies-per-second)))
(def (emit-memory-receipt receipt)
  (parameterize ((current-output-port (current-error-port)))
    (yuanxu-write-observation-line! "debug-memory %s"
      (yuanxu-debug-memory-receipt-sexp receipt))))
(def (memory-anomaly receipt)
  (let (failure
        (YuanxuDebugMemoryAnomaly
         "Yuanxu debug memory policy rejected the observed phase"
         irritants: '()))
    (set! (YuanxuDebugMemoryAnomaly-receipt failure) receipt)
    failure))
(def (yuanxu-debug-raise-memory-anomaly receipt)
  (raise (memory-anomaly receipt)))


;; Counter 7 is VM-reported allocation. Counter 16 describes only the latest
;; GC cycle and cannot be used for allocation deltas. Source-only qualification
;; observed counter 7 move backwards: the Case flags that stream invalid rather
;; than silently clamping it into performance evidence. The other counters below
;; remain last-GC snapshots, not exclusive byte ownership by a test.
(def (yuanxu-debug-memory-counters collect?)
  (when collect? (##gc))
  (let* ((stats (##process-statistics))
         (allocated (inexact->exact (f64vector-ref stats 7))))
    (list (inexact->exact (f64vector-ref stats 15))
          (max 0 allocated)
          (inexact->exact (f64vector-ref stats 17))
          (inexact->exact (f64vector-ref stats 18))
          (inexact->exact (f64vector-ref stats 19)))))

(def (yuanxu-debug-memory-sample-from-counters phase counters)
    (apply (lambda (heap-size allocation live movable still)
             (yuanxu-debug-memory-sample
              phase heap-size allocation live movable still))
           counters))

(def (yuanxu-debug-memory-snapshot phase collect?: (collect? #f))
  (unless (and (symbol? phase) (boolean? collect?))
    (error "invalid Yuanxu debug memory snapshot request" phase collect?))
  (yuanxu-debug-memory-sample-from-counters
   phase (yuanxu-debug-memory-counters collect?)))

;;; Periodic monitor ticks stay scalar-only while the test worker is active.
;;; POO construction and Contract validation resume only after the worker has
;;; stopped, avoiding cross-thread validation races in instrumented tests.
(def (yuanxu-debug-memory-counters-rejected?
      heap-limit live-growth-limit baseline-counters counters)
  (let ((heap-size (list-ref counters 0))
        (live (list-ref counters 2)))
    (or (> heap-size heap-limit)
        (> (- live (list-ref baseline-counters 2)) live-growth-limit))))

(def (duration-receipt phase-value policy-label-value limit-value elapsed-value reason-value)
          (validate YuanxuDebugDurationReceiptContract
            (.o (:: @ DebugDurationReceipt.)
                phase: phase-value
                policy-label: policy-label-value
                limit-milliseconds: limit-value
                elapsed-milliseconds: elapsed-value
                accepted?: #f
                reason: reason-value)))
(def (duration-anomaly receipt limit elapsed reason)
  (let (failure
          (YuanxuDebugDurationAnomaly
           "Yuanxu testing Case duration budget exceeded"
           irritants: (list reason limit elapsed)))
    (set! (YuanxuDebugDurationAnomaly-receipt failure) receipt)
    failure))
(def (yuanxu-debug-raise-duration-anomaly phase policy-label limit elapsed
        reason: (reason 'duration-exceeded))
  (raise (duration-anomaly
           (duration-receipt phase policy-label limit elapsed reason)
           limit elapsed reason)))

;; : (-> YuanxuDebugMemoryPolicy YuanxuDebugMemorySample Symbol port: OutputPort emit?: Boolean YuanxuDebugMemoryReceipt)
;; yuanxu-debug-memory-checkpoint
;;   : (-> YuanxuDebugMemoryPolicy YuanxuDebugMemorySample Symbol port: OutputPort emit?: Boolean YuanxuDebugMemoryReceipt)
;;   | doc m%
;;       Sample one policy checkpoint and return its typed POO receipt, raising
;;       the same receipt as an anomaly when fail-closed policy rejects it.
;;       The specialized emission branch projects only bounded scalar evidence;
;;       it never changes the receipt used for the policy decision.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-debug-memory-checkpoint policy baseline 'compile)
;;       ;; => YuanxuDebugMemoryReceipt
;;       ```
;;     %
(def (yuanxu-debug-memory-checkpoint policy baseline phase
                                       port: (port (current-error-port))
                                       emit?: (emit? #f))
  (unless (and (output-port? port) (boolean? emit?))
    (error "invalid Yuanxu debug memory checkpoint output request"))
  (let* ((after
          (yuanxu-debug-memory-snapshot
           phase collect?: (.ref policy 'collect-before-sample?)))
         (receipt (yuanxu-debug-memory-receipt policy baseline after)))
    (when emit?
      (parameterize ((current-error-port port))
        (emit-memory-receipt receipt)))
    (when (and (not (.ref receipt 'accepted?))
               (.ref policy 'fail-closed?))
      (yuanxu-debug-raise-memory-anomaly receipt))
    receipt))

;;; A span adds in-band phase evidence around one development operation. Long
;;; operations should expose intermediate checkpoints; the test entrypoint's
;;; declarative runtime profile remains the final pre-suite heap boundary.
;; : (forall (a) (-> YuanxuDebugMemoryPolicy Symbol (-> a) port: OutputPort emit?: Boolean (values a YuanxuDebugMemoryReceipt)))
;; call-with-yuanxu-debug-memory-span
;;   : (-> YuanxuDebugMemoryPolicy Symbol (-> Object) port: OutputPort emit?: Boolean (values Object YuanxuDebugMemoryReceipt))
;;   | doc m%
;;       Measure one returning development operation and preserve its value
;;       beside a typed POO receipt for the observed heap delta.
;;       The specialized branch evaluates the operation exactly once before
;;       the final checkpoint, so sampling cannot duplicate user effects.
;;
;;       # Examples
;;
;;       ```scheme
;;       (call-with-yuanxu-debug-memory-span policy 'compile (lambda () 'ok))
;;       ;; => (values 'ok YuanxuDebugMemoryReceipt)
;;       ```
;;     %
(def (call-with-yuanxu-debug-memory-span policy phase thunk
                                           port: (port (current-error-port))
                                           emit?: (emit? #f))
  (unless (procedure? thunk)
    (error "Yuanxu debug memory span requires a thunk"))
  (let (before
        (yuanxu-debug-memory-snapshot
         phase collect?: (.ref policy 'collect-before-sample?)))
    (let (value (thunk))
      (values value
              (yuanxu-debug-memory-checkpoint
               policy before phase port: port emit?: emit?)))))

;;; The monitored form is the asynchronous debug boundary: the observed
;;; operation runs in a Scheme thread while its owner samples from the calling
;;; thread. Native POO cycle failures propagate immediately; non-returning
;;; operations remain subject to the monitor's memory and duration limits.
;;; The test entrypoint applies Gambit's heap boundary declaratively before the
;;; suites load; this monitor adds phase-attributed growth evidence in-band.
;; : (forall (a) (-> YuanxuDebugMemoryPolicy Symbol (-> a) port: OutputPort emit?: Boolean (values a YuanxuDebugMemoryReceipt)))
;; call-with-yuanxu-debug-memory-monitor
;;   : (-> YuanxuDebugMemoryPolicy Symbol (-> Object) port: OutputPort emit?: Boolean (values Object YuanxuDebugMemoryReceipt))
;;   | doc m%
;;       Run one development operation in a native Scheme worker while the
;;       caller samples bounded heap counters and enforces its POO policy.
;;       The specialized timeout branch preserves the worker's lexical result
;;       or exception and terminates it only after a fail-closed anomaly.
;;
;;       # Examples
;;
;;       ```scheme
;;       (call-with-yuanxu-debug-memory-monitor policy 'compile (lambda () 'ok))
;;       ;; => (values 'ok YuanxuDebugMemoryReceipt)
;;       ```
;;     %
(def (call-with-yuanxu-debug-memory-monitor policy phase thunk
                                              port: (port (current-error-port))
                                              emit?: (emit? #f)
                                              max-duration-milliseconds:
                                              (max-duration-milliseconds #f))
  (unless (procedure? thunk)
    (error "Yuanxu debug memory monitor requires a thunk"))
  (unless (or (not max-duration-milliseconds)
              (and (exact-integer? max-duration-milliseconds)
                   (> max-duration-milliseconds 0)))
    (error "invalid Yuanxu debug Case duration limit"
           max-duration-milliseconds))
  (let* ((policy-label (.ref policy 'label))
         (started-jiffy (current-jiffy))
         (collect-before-sample? (.ref policy 'collect-before-sample?))
         (fail-closed? (.ref policy 'fail-closed?))
         (sample-interval-milliseconds
          (.ref policy 'sample-interval-milliseconds))
         (baseline-counters
          (yuanxu-debug-memory-counters
           collect-before-sample?))
         (heap-limit (.ref policy 'heap-limit-bytes))
         (live-growth-limit (.ref policy 'live-growth-limit-bytes))
         (timeout-token (cons 'yuanxu-debug-memory-timeout '()))
         (interval-seconds
          (/ (max 1 sample-interval-milliseconds) 1000.0))
         (worker
          (make-thread
           (lambda ()
             (with-exception-catcher
              (lambda (failure) (cons 'failure failure))
              (lambda ()
                (let* ((worker-policy
                        (yuanxu-debug-memory-policy
                         policy-label
                         heap-limit-bytes: heap-limit
                         live-growth-limit-bytes: live-growth-limit
                         sample-interval-milliseconds:
                         sample-interval-milliseconds
                         collect-before-sample?: collect-before-sample?
                         fail-closed?: fail-closed?))
                       (baseline
                        (yuanxu-debug-memory-sample-from-counters
                         phase baseline-counters))
                       (value (thunk))
                       (receipt
                        (yuanxu-debug-memory-checkpoint
                         worker-policy baseline phase
                         port: port emit?: emit?)))
                  (cons 'value (cons value receipt))))))))
         (joined? #f))
    (thread-start! worker)
    (dynamic-wind
      (lambda () #!void)
      (lambda ()
        (let monitor ()
          (let (outcome
                (thread-join! worker interval-seconds timeout-token))
            (if (eq? outcome timeout-token)
              (let (counters (yuanxu-debug-memory-counters #f))
                (if (yuanxu-debug-memory-counters-rejected?
                     heap-limit live-growth-limit baseline-counters counters)
                  (begin
                    (thread-terminate! worker)
                    (set! joined? #t)
                    (let* ((baseline
                            (yuanxu-debug-memory-sample-from-counters
                             phase baseline-counters))
                           (after
                            (yuanxu-debug-memory-sample-from-counters
                             phase counters))
                           (receipt
                            (yuanxu-debug-memory-receipt
                             policy baseline after)))
                      (when emit?
                        (parameterize ((current-error-port port))
                          (emit-memory-receipt receipt)))
                      (yuanxu-debug-raise-memory-anomaly receipt)))
                  (let (elapsed
                        (yuanxu-debug-elapsed-milliseconds started-jiffy))
                    (if (and max-duration-milliseconds
                             (>= elapsed max-duration-milliseconds))
                      (begin
                        (thread-terminate! worker)
                        (set! joined? #t)
                        (yuanxu-debug-raise-duration-anomaly
                         phase policy-label
                         max-duration-milliseconds elapsed))
                      (monitor)))))
              (begin
                (set! joined? #t)
                (if (eq? (car outcome) 'failure)
                  (raise (cdr outcome))
                  (values (cadr outcome) (cddr outcome))))))))
      (lambda ()
        (unless joined?
          (thread-terminate! worker))))))

;;; Native std/test checks use a continuation installed by the harness.  The
;;; Case body must therefore remain on the harness thread.  Only the sampler
;;; runs on a separate Scheme thread and interrupts the owner on rejection.
;;; Heap counters remain process-wide; this is not a thread-local heap quota.
(def (call-with-yuanxu-debug-memory-case-watchdog
      policy phase thunk
      port: (port (current-error-port))
      emit?: (emit? #f)
      max-duration-milliseconds: (max-duration-milliseconds 60000))
  (unless (and (procedure? thunk)
               (symbol? phase)
               (output-port? port)
               (boolean? emit?)
               (exact-integer? max-duration-milliseconds)
               (> max-duration-milliseconds 0))
    (error "invalid Yuanxu testing Case watchdog request"
           phase max-duration-milliseconds))
  (let* ((owner (current-thread))
         (gate (make-mutex))
         (done? #f)
         (started-jiffy (current-jiffy))
         (interval-seconds
          (/ (max 1 (.ref policy 'sample-interval-milliseconds)) 1000.0))
         (baseline-counters
          (yuanxu-debug-memory-counters
           (.ref policy 'collect-before-sample?)))
         (heap-limit (.ref policy 'heap-limit-bytes))
         (live-growth-limit (.ref policy 'live-growth-limit-bytes))
         (collect-before-sample? (.ref policy 'collect-before-sample?))
         (policy-label (.ref policy 'label))
         (fail-closed? (.ref policy 'fail-closed?)))
    (def stopped #f)
    (def rendered? #f)
    (def (stop! kind data)
      (def failure
        (if (eq? kind 'memory) (memory-anomaly #f)
          (duration-anomaly #f (car data) (cadr data) (caddr data))))
      (set! stopped (make-case-stop failure kind data))
      (raise failure))
    (def (claim-stop!)
      (mutex-lock! gate)
      (let (claimed? (not done?))
        (when claimed? (set! done? #t))
        (mutex-unlock! gate)
        claimed?))
    (def (finish!)
      (mutex-lock! gate)
      (set! done? #t)
      (mutex-unlock! gate))
    (def (watch)
      (thread-sleep! interval-seconds)
      (unless done?
        (let* ((counters (yuanxu-debug-memory-counters collect-before-sample?))
               (elapsed (yuanxu-debug-elapsed-milliseconds started-jiffy))
               (progress (and (pair? (current-execution-progress))
                              (car (current-execution-progress))))
               (progress-status (and progress (execution-progress-status progress))))
          (cond
           ((and fail-closed?
                 (yuanxu-debug-memory-counters-rejected?
                  heap-limit live-growth-limit baseline-counters counters))
            (when (claim-stop!)
              (thread-interrupt!
               owner
               (lambda () (stop! 'memory counters)))))
           ((or (>= elapsed max-duration-milliseconds) progress-status)
            (when (claim-stop!)
              ;; The interrupted owner may currently be inside a different,
              ;; nested Ops progress extent. Preserve the triggering watchdog's
              ;; state; do not relabel an idle stop as a total-budget failure.
              (let* ((idle? (eq? progress-status 'idle))
                     (limit (if idle? (execution-progress-limit progress 'idle)
                                max-duration-milliseconds))
                     (observed (if idle? (execution-progress-idle-milliseconds progress)
                                   elapsed)))
                (thread-interrupt! owner
                  (lambda ()
                    (stop! 'duration
                      (list limit observed
                            (if idle? 'idle-exceeded 'duration-exceeded)))))))))
          (unless done? (watch)))))
    (def (render-stop!)
      (when (and stopped (not rendered?))
        (set! rendered? #t)
        (with-catch
          (lambda (diagnostic-failure)
            (error "Case rejection and diagnostic construction failed"
              (case-stop-failure stopped) diagnostic-failure))
          (lambda ()
            (case (case-stop-kind stopped)
              ((memory)
               (let (receipt
                      (yuanxu-debug-memory-receipt policy
                        (yuanxu-debug-memory-sample-from-counters phase baseline-counters)
                        (yuanxu-debug-memory-sample-from-counters
                          phase (case-stop-data stopped))))
                 (when emit?
                   (parameterize ((current-error-port port)) (emit-memory-receipt receipt)))
                 (set! (YuanxuDebugMemoryAnomaly-receipt (case-stop-failure stopped)) receipt)))
              ((duration)
               (let (data (case-stop-data stopped))
                 (set! (YuanxuDebugDurationAnomaly-receipt (case-stop-failure stopped))
                   (duration-receipt phase policy-label (car data) (cadr data) (caddr data))))))))))
    (def (run-operation)
      (with-catch
        (lambda (failure) (render-stop!) (raise failure))
        (lambda ()
          (def value (thunk))
          ;; A body cannot turn a claimed fail-closed stop into acceptance by
          ;; swallowing its exception. Keep that same condition and origin.
          (when stopped (render-stop!) (raise (case-stop-failure stopped)))
          value)))
    (let (watchdog (make-thread watch))
      (thread-start! watchdog)
      (dynamic-wind
        void
        (lambda ()
          (let (value (run-operation))
            (finish!)
            (let (after-counters
                  (yuanxu-debug-memory-counters
                   (.ref policy 'collect-before-sample?)))
              (if (or emit?
                      (yuanxu-debug-memory-counters-rejected?
                       heap-limit live-growth-limit
                       baseline-counters after-counters))
                (let* ((before
                        (yuanxu-debug-memory-sample-from-counters
                         phase baseline-counters))
                       (after
                        (yuanxu-debug-memory-sample-from-counters
                         phase after-counters))
                       (receipt
                        (yuanxu-debug-memory-receipt
                         policy before after)))
                  (when emit?
                    (parameterize ((current-error-port port))
                      (emit-memory-receipt receipt)))
                  (when (and fail-closed?
                             (not (.ref receipt 'accepted?)))
                    (yuanxu-debug-raise-memory-anomaly receipt))
                  (values value receipt))
                (values value #f)))))
        (lambda ()
          (finish!)
          (thread-terminate! watchdog))))))

