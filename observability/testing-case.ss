;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A POO policy around native std/test cases.  This does not own test
;;; discovery, assertion semantics, or the gxtest runner.
(import (only-in :std/test test-case)
        (only-in :yuanxu/ops/progress call-with-execution-progress execution-progress!
                 execution-idle-seconds execution-total-seconds)
        (only-in :clan/poo/object .call .o .cc .ref .slot? object?)
        (only-in :gerbil/expander core-resolve-identifier core-context-root
                 feature-binding? current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/memory
                 yuanxu-debug-memory-policy
                 yuanxu-debug-allocation-current?
                 yuanxu-debug-cpu-microseconds
                 yuanxu-debug-memory-snapshot yuanxu-debug-memory-checkpoint
                 call-with-yuanxu-debug-memory-case-watchdog))

(export yuanxu-testing-case-profile-prototype
        yuanxu-testing-case-profile?
        yuanxu-default-testing-case-profile
        yuanxu-current-testing-case-profile
        yuanxu-selected-testing-case-profile
        yuanxu-test-checkpoint
        yuanxu-test-observe
        yuanxu-test-case
        yuanxu-test-case/with)

;;; All declared Yuanxu cases receive this default.  The heap counters are
;;; process-wide, so the memory policy is a guard on a Case execution span,
;;; not a claim of independent thread-local heap accounting.  Assertions stay
;;; on the native harness thread; a separate sampler may interrupt it.  The native
;;; worker's hard managed-heap cap is set by the Testing Interface.
(def yuanxu-testing-case-profile-prototype
  (.o (testing-case-profile? #t)
      (identity 'testing/default-case)
      (heap-limit-bytes 2147483648)
      ;; Keep the existing half-budget growth policy when the heap is refined.
      (live-growth-limit-bytes (quotient heap-limit-bytes 2))
      (sample-interval-milliseconds 10)
      (collect-before-sample? #f)
      (fail-closed? #t)
      (max-duration-milliseconds (* 1000 execution-total-seconds))
      (max-idle-milliseconds (* 1000 execution-idle-seconds))
      (emit? #f)
      .run: (lambda (self description thunk)
              (let (problem (yuanxu-testing-case-profile-problem self))
                (when problem
                  (error "invalid Yuanxu testing Case profile"
                         problem)))
              (unless (and (string? description) (procedure? thunk))
                (error "invalid Yuanxu testing Case" description thunk))
              (def policy
               (yuanxu-debug-memory-policy
                (.ref self 'identity)
                heap-limit-bytes: (.ref self 'heap-limit-bytes)
                live-growth-limit-bytes:
                (.ref self 'live-growth-limit-bytes)
                sample-interval-milliseconds:
                (.ref self 'sample-interval-milliseconds)
                collect-before-sample?:
                (.ref self 'collect-before-sample?)
                fail-closed?: (.ref self 'fail-closed?)))
              ;; Runtime phase observations belong to this Case invocation.
              ;; The default is inert. Emission uses the same policy, samples
              ;; and receipt Contract as the existing watchdog, not a sampler.
              (def observing? (.ref self 'emit?))
              (def baseline
                (and observing? (yuanxu-debug-memory-snapshot 'case-entry)))
              (def started (and observing? (current-jiffy)))
              (def started-cpu
                (and observing? (yuanxu-debug-cpu-microseconds)))
              (def counts (and observing? (make-hash-table-eq)))
              (def checkpoint-wall 0)
              (def checkpoint-cpu-total 0)
              (def allocation-previous #f)
              (def allocation-current? #t)
              (def (observe key amount)
                (unless (and (symbol? key) (exact-integer? amount) (>= amount 0))
                  (error "test work observation requires a symbol and natural count" key amount))
                (when (and (not (hash-key? counts key)) (>= (hash-length counts) 64))
                  (error "test work observation exceeded its bounded categories" key (hash-keys counts)))
                (let (next (+ (or (hash-get counts key) 0) amount))
                  (hash-put! counts key next) next))
              (def (observed-checkpoint phase)
                (def checkpoint-started (current-jiffy))
                (def checkpoint-cpu (yuanxu-debug-cpu-microseconds))
                (let (receipt (yuanxu-debug-memory-checkpoint
                                policy baseline phase emit?: #t))
                  (yuanxu-write-observation-line!
                    "test-phase %s elapsed-ms=%s cpu-ms=%s process-cpu-ms=%s" phase
                    (quotient (* (- (current-jiffy) started) 1000)
                              (jiffies-per-second))
                    (quotient (- (yuanxu-debug-cpu-microseconds) started-cpu) 1000)
                    ;; Includes native source imports before the Case begins.
                    ;; This is the existing SDK process counter, not a probe or
                    ;; a claim that parent and worker CPU clocks share an epoch.
                    (quotient (yuanxu-debug-cpu-microseconds) 1000))
                  (def allocated (.ref (.ref receipt 'after) 'allocated-bytes))
                  (set! allocation-current?
                    (yuanxu-debug-allocation-current? allocation-current?
                      (or allocation-previous (.ref (.ref receipt 'before) 'allocated-bytes))
                      allocated))
                  (set! allocation-previous allocated)
                  (yuanxu-write-observation-line!
                    "test-work phase=%s allocation-current?=%s counts=%s"
                    phase allocation-current? (hash->list counts))
                  ;; Attribute explicit receipt construction/output separately
                  ;; from domain work. Scalar source-event accounting and the
                  ;; watchdog remain outside this deliberately narrow measure.
                  (set! checkpoint-wall (+ checkpoint-wall
                    (quotient (* (- (current-jiffy) checkpoint-started) 1000000)
                              (jiffies-per-second))))
                  (set! checkpoint-cpu-total (+ checkpoint-cpu-total
                    (- (yuanxu-debug-cpu-microseconds) checkpoint-cpu)))
                  receipt))
              (parameterize ((current-case-checkpoint (if counts observed-checkpoint void))
                             (current-case-observer (and counts observe)))
                (dynamic-wind
                  void
                  (lambda ()
                    (call-with-execution-progress
                      (.ref self 'max-idle-milliseconds)
                      (.ref self 'max-duration-milliseconds)
                      (lambda (_progress)
                        (yuanxu-test-checkpoint 'case-enter)
                        (call-with-yuanxu-debug-memory-case-watchdog
                          policy (string->symbol description) thunk
                          emit?: (.ref self 'emit?)
                          max-duration-milliseconds:
                          (.ref self 'max-duration-milliseconds)))))
                  (lambda ()
                    (when counts
                      (yuanxu-write-observation-line!
                        "test-case-timing case=%s elapsed-ms=%s cpu-ms=%s checkpoint-us=%s checkpoint-cpu-us=%s"
                        description
                        (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second))
                        (quotient (- (yuanxu-debug-cpu-microseconds) started-cpu) 1000)
                        checkpoint-wall checkpoint-cpu-total)
                      (yuanxu-write-observation-line!
                        "test-work case=%s allocation-current?=%s final-counts=%s"
                        description allocation-current? (hash->list counts)))))))))

(def current-case-checkpoint (make-parameter void))
(def current-case-observer (make-parameter #f))
(def (yuanxu-test-observe key (amount 1))
  ;; Only scalar totals escape into a Case-owned table. No source context,
  ;; syntax, candidate object or callback result becomes an observation root.
  (let (observe (current-case-observer))
    (if observe (observe key amount) 0)))
(def (yuanxu-test-checkpoint phase)
  (unless (symbol? phase) (error "test checkpoint requires a phase symbol" phase))
  ;; A completed named boundary counts once, even when emission is disabled.
  (execution-progress! (list 'checkpoint phase) 1)
  ((current-case-checkpoint) phase))

(def (yuanxu-testing-case-profile-problem value)
  (cond
   ((not (object? value)) 'not-poo-object)
   ((or (not (.slot? value 'testing-case-profile?))
        (not (eq? (.ref value 'testing-case-profile?) #t)))
    'missing-case-profile-marker)
   ((or (not (.slot? value 'identity))
        (not (symbol? (.ref value 'identity))))
    'invalid-identity)
   ((.slot? value 'memory-policy)
    'unexpected-memory-policy-slot)
   ((or (not (.slot? value 'heap-limit-bytes))
        (not (exact-integer? (.ref value 'heap-limit-bytes)))
        (< (.ref value 'heap-limit-bytes) 0))
    'invalid-heap-limit)
   ((or (not (.slot? value 'live-growth-limit-bytes))
        (not (exact-integer? (.ref value 'live-growth-limit-bytes)))
        (< (.ref value 'live-growth-limit-bytes) 0))
    'invalid-live-growth-limit)
   ((or (not (.slot? value 'sample-interval-milliseconds))
        (not (exact-integer?
              (.ref value 'sample-interval-milliseconds)))
        (<= (.ref value 'sample-interval-milliseconds) 0))
    'invalid-sample-interval)
   ((or (not (.slot? value 'collect-before-sample?))
        (not (boolean? (.ref value 'collect-before-sample?))))
    'invalid-collection)
   ((or (not (.slot? value 'fail-closed?))
        (not (boolean? (.ref value 'fail-closed?))))
    'invalid-fail-closed)
   ((or (not (.slot? value 'max-duration-milliseconds))
        (not (exact-integer? (.ref value 'max-duration-milliseconds)))
        (<= (.ref value 'max-duration-milliseconds) 0))
    'invalid-duration)
   ((or (not (.slot? value 'max-idle-milliseconds))
        (not (exact-integer? (.ref value 'max-idle-milliseconds)))
        (<= (.ref value 'max-idle-milliseconds) 0))
    'invalid-idle-duration)
   ((or (not (.slot? value 'emit?))
        (not (boolean? (.ref value 'emit?))))
    'invalid-emission)
   ((and (.slot? value 'trace-enabled?)
         (not (boolean? (.ref value 'trace-enabled?))))
    'invalid-trace)
   ((or (not (.slot? value '.run))
        (not (procedure? (.ref value '.run))))
    'missing-run-slot)
   (else #f)))

(def (yuanxu-testing-case-profile? value)
  (not (yuanxu-testing-case-profile-problem value)))

(def yuanxu-default-testing-case-profile
  (.o (:: @ yuanxu-testing-case-profile-prototype)))

(def yuanxu-current-testing-case-profile
  (make-parameter yuanxu-default-testing-case-profile))

;; The native harness binds -D features in its root before importing tests.
;; Resolve at execution time, including for compiled test modules. A lexical
;; cond-expand here would freeze the build process's observation decision.
(def module-observation-profile
  (delay
    ;; Capture native harness features before entering the private import frame.
    (let (trace? (feature-binding?
                  (core-resolve-identifier 'yuanxu-module-test-trace 0 (core-context-root))))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :yuanxu/module-system/building/test-observation))
        (.cc (eval-syntax 'ModuleTestingProfile.) 'emit? #t 'trace-enabled? trace?)))))
(def (yuanxu-selected-testing-case-profile)
  (let (profile (yuanxu-current-testing-case-profile))
    (if (and (eq? profile yuanxu-default-testing-case-profile)
             (feature-binding?
               (core-resolve-identifier 'yuanxu-module-test-observation
                                        0 (core-context-root))))
      (force module-observation-profile)
      profile)))

;;; Hygienic syntax projects directly to the upstream test-case macro.  The
;;; native harness still registers and reports the resulting TestCase.
(defrules yuanxu-test-case ()
  ((_ description body rest ...)
   (yuanxu-test-case/with
    (yuanxu-selected-testing-case-profile)
    description body rest ...)))

(defrules yuanxu-test-case/with ()
  ((_ profile description body rest ...)
   (test-case description
     (let (active-profile profile)
       (call-with-values
        (lambda ()
          (.call active-profile .run active-profile description
                 (lambda () body rest ...)))
        (lambda (value receipt) value))))))
