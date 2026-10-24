;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: pure bounded inspection of existing Contract evidence.
;;; Never re-evaluates the observed candidate, reads a clock, or prints a value.
;;; Canonical library imports retain one descriptor/prototype identity when
;;; source consumers and compiled owners share the same process.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :clan/poo/mop validate raise-type-error)
        (only-in :yuanxu/object-types/contracts YuanxuValidationEvidence)
        :yuanxu/observability/types)
(export yuanxu-observation-admission-facts
        yuanxu-observation-admission-explanation
        yuanxu-observation-admission-summary
        yuanxu-observation-summary-sexp
        yuanxu-debug-call-policy
        yuanxu-debug-call-receipt
        yuanxu-debug-call-receipt-sexp
        yuanxu-debug-slot-policy
        yuanxu-debug-slot-receipt
        yuanxu-debug-slot-receipt-sexp
        yuanxu-debug-memory-policy
        yuanxu-debug-memory-policy?
        yuanxu-debug-memory-sample
        yuanxu-debug-memory-receipt
        yuanxu-debug-memory-receipt-sexp
        yuanxu-debug-allocation-current?)

;;; Stable contract prototypes are resolved at module load, outside every
;;; constructor and receipt path.
(def ObservationFailure. (.ref YuanxuObservationFailureContract 'proto))
(def AdmissionFacts. (.ref YuanxuAdmissionObservationFactsContract 'proto))
(def ObservationSummary. (.ref YuanxuObservationSummaryContract 'proto))
(def DebugCallPolicy. (.ref YuanxuDebugCallPolicyContract 'proto))
(def DebugCallReceipt. (.ref YuanxuDebugCallReceiptContract 'proto))
(def DebugSlotPolicy. (.ref YuanxuDebugSlotPolicyContract 'proto))
(def DebugSlotReceipt. (.ref YuanxuDebugSlotReceiptContract 'proto))
(def DebugMemoryPolicy. (.ref YuanxuDebugMemoryPolicyContract 'proto))
(def DebugMemorySample. (.ref YuanxuDebugMemorySampleContract 'proto))
(def DebugMemoryReceipt. (.ref YuanxuDebugMemoryReceiptContract 'proto))

(def (yuanxu-observation-validate-receipt receipt)
  (validate YuanxuValidationEvidence receipt)
  (unless (eq? (.ref receipt 'contract-identity)
               (.ref (.ref receipt 'classification) 'type-identity))
    (raise-type-error YuanxuValidationEvidence receipt))
  receipt)

(def (yuanxu-observation-failure-code receipt)
  (let* ((classification (.ref receipt 'classification))
         (classified? (.ref classification 'accepted?))
         (diagnostics (if classified? (.ref receipt 'obligation-evidence)
                         (.ref classification 'diagnostics)))
         (first (and (pair? diagnostics) (car diagnostics))))
    (cond
     ((symbol? first) first)
     ((and (object? first) (.slot? first 'reason) (symbol? (.ref first 'reason)))
      (.ref first 'reason))
     ((and (object? first) (.slot? first 'code) (symbol? (.ref first 'code)))
      (.ref first 'code))
     ((and (object? first) (.slot? first 'kind) (symbol? (.ref first 'kind)))
      (.ref first 'kind))
     (classified? 'obligation-rejected)
     (else 'classification-rejected))))

(def (yuanxu-observation-failure receipt path-value)
  (let ((contract-value (.ref receipt 'contract-identity))
        (code-value (yuanxu-observation-failure-code receipt)))
    (.o (:: @ ObservationFailure.)
        path: path-value contract: contract-value code: code-value)))

;;; The returned values are failures, completeness, and visited receipt count.
;;; A repeated receipt is an incomplete inspection, not a Module cycle claim.
(def (yuanxu-observation-inspect receipt path budget ancestors)
  (cond
   ((or (zero? budget) (memq receipt ancestors)) (values '() #f 0))
   (else
    (yuanxu-observation-validate-receipt receipt)
    (cond
     ((.ref receipt 'accepted?) (values '() #t 1))
     ((not (.ref (.ref receipt 'classification) 'accepted?))
      (values (list (yuanxu-observation-failure receipt path)) #t 1))
     ((and (.slot? receipt 'responsibility-evidence)
           (pair? (.ref receipt 'responsibility-evidence)))
      (let (children (.ref receipt 'responsibility-evidence))
        (unless (list? children) (error "invalid observation responsibility evidence"))
        (let-values (((failures complete? inspected)
                      (yuanxu-observation-inspect-children
                       children path (1- budget) (cons receipt ancestors))))
          ;; Object-level obligations can fail after every field was accepted.
          (values (if (and complete? (null? failures))
                    (list (yuanxu-observation-failure receipt path)) failures)
                  complete? (1+ inspected)))))
     (else (values (list (yuanxu-observation-failure receipt path)) #t 1))))))

(def (yuanxu-observation-inspect-children children path budget ancestors)
  (cond
   ((null? children) (values '() #t 0))
   ((zero? budget) (values '() #f 0))
   (else
    (let (child (car children))
      (unless (and (object? child) (.slot? child 'responsibility)
                   (symbol? (.ref child 'responsibility)))
        (error "invalid observation responsibility identity"))
      (let-values (((failures complete? inspected)
                    (yuanxu-observation-inspect
                     child (append path (list (.ref child 'responsibility))) budget ancestors)))
        (if (not complete?)
          (values failures #f inspected)
          (let-values (((tail-failures tail-complete? tail-inspected)
                        (yuanxu-observation-inspect-children
                         (cdr children) path (- budget inspected) ancestors)))
            (values (append failures tail-failures) tail-complete?
                    (+ inspected tail-inspected)))))))))

(def (yuanxu-observation-admission-facts receipt context)
  (validate YuanxuObservationContextContract context)
  (yuanxu-observation-validate-receipt receipt)
  (let-values (((failure-values complete-value inspected-value)
                (yuanxu-observation-inspect receipt '() (.ref context 'detail-budget) '())))
    (let ((contract-value (.ref receipt 'contract-identity))
          (accepted-value (.ref receipt 'accepted?))
          (classified-value (.ref (.ref receipt 'classification) 'accepted?))
          (obligation-count-value (length (.ref receipt 'obligation-evidence))))
      (validate YuanxuAdmissionObservationFactsContract
        (.o (:: @ AdmissionFacts.)
            contract: contract-value accepted?: accepted-value
            classification-accepted?: classified-value obligation-count: obligation-count-value
            failures: failure-values detail-complete?: complete-value
            inspected-count: inspected-value)))))

;;; The summary is a fresh bounded aggregate projection. It does not carry the
;;; candidate, raw context, free-form diagnostic strings, identities, or paths.
(def (yuanxu-observation-admission-summary observation)
  (validate YuanxuAdmissionObservationContract observation)
  (let* ((facts (.ref observation 'evidence))
         (accepted-value (.ref facts 'accepted?))
         (complete-value (.ref facts 'detail-complete?))
         (count-value (length (.ref facts 'failures)))
         (inspected-value (.ref facts 'inspected-count)))
    (.o (:: @ ObservationSummary.)
        accepted?: accepted-value detail-complete?: complete-value
        failure-count: count-value inspected-count: inspected-value)))

;;; An internal explanation carries semantic correlation and bounded field
;;; paths. It is not the default development-output projection.
(def (yuanxu-observation-admission-explanation observation)
  (let ((summary (yuanxu-observation-admission-summary observation))
        (source-value (.ref observation 'source))
        (generation-value (.ref observation 'generation))
        (causes-value (.ref observation 'causes))
        (provenance-value (.ref observation 'provenance))
        (failure-values (.ref (.ref observation 'evidence) 'failures))
        (contract-value (.ref (.ref observation 'evidence) 'contract))
        (obligation-count-value (.ref (.ref observation 'evidence) 'obligation-count))
        (classified-value (.ref (.ref observation 'evidence) 'classification-accepted?)))
    (.o (:: @ summary) source: source-value generation: generation-value
        causes: causes-value provenance: provenance-value failures: failure-values
        contract: contract-value obligation-count: obligation-count-value
        classification-accepted?: classified-value)))

(def (yuanxu-observation-summary-sexp summary)
  (validate YuanxuObservationSummaryContract summary)
  (list 'admission-observation
        (list 'accepted? (.ref summary 'accepted?))
        (list 'detail-complete? (.ref summary 'detail-complete?))
        (list 'failure-count (.ref summary 'failure-count))
        (list 'inspected-count (.ref summary 'inspected-count))))

;; : (-> Symbol Natural YuanxuDebugCallPolicy)
(def (yuanxu-debug-call-policy label-value maximum-depth-value)
  (unless (> maximum-depth-value 0)
    (error "Yuanxu debug call depth must be positive" maximum-depth-value))
  (validate YuanxuDebugCallPolicyContract
    (.o (:: @ DebugCallPolicy.)
        label: label-value
        maximum-depth: maximum-depth-value)))

;; : (-> YuanxuDebugCallPolicy Symbol Natural [Symbol] Symbol Symbol Natural YuanxuDebugCallReceipt)
(def (yuanxu-debug-call-receipt policy call-value depth-value path-value
                                  operator-kind-value outcome-value
                                  (elapsed-nanoseconds-value 0))
  (validate YuanxuDebugCallPolicyContract policy)
  (let* ((policy-value policy)
         (accepted-value (memq outcome-value '(admitted returned)))
         (reason-value
          (case outcome-value
            ((admitted) 'call-admitted)
            ((returned) 'call-returned)
            ((raised) 'call-raised)
            ((rejected-non-procedure) 'non-procedure-operator)
            ((rejected-cycle) 'recursive-call-cycle)
            ((rejected-depth) 'maximum-call-depth-exceeded)
            (else 'invalid-call-outcome))))
    (validate YuanxuDebugCallReceiptContract
      (.o (:: @ DebugCallReceipt.)
          policy: policy-value
          call: call-value
          depth: depth-value
          active-path: path-value
          operator-kind: operator-kind-value
          outcome: outcome-value
          elapsed-nanoseconds: elapsed-nanoseconds-value
          accepted?: (if accepted-value #t #f)
          reason: reason-value))))

;;; The renderer is deliberately closed: it cannot force or retain arguments,
;;; results, a POO receiver, or an exception while reporting a bad call edge.
(def (yuanxu-debug-call-receipt-sexp receipt)
  (validate YuanxuDebugCallReceiptContract receipt)
  (list 'debug-call-observation
        (list 'label (.ref (.ref receipt 'policy) 'label))
        (list 'call (.ref receipt 'call))
        (list 'depth (.ref receipt 'depth))
        (list 'active-path (.ref receipt 'active-path))
        (list 'operator-kind (.ref receipt 'operator-kind))
        (list 'outcome (.ref receipt 'outcome))
        (list 'elapsed-nanoseconds (.ref receipt 'elapsed-nanoseconds))
        (list 'accepted? (.ref receipt 'accepted?))
        (list 'reason (.ref receipt 'reason))))

;; : (-> Symbol Natural YuanxuDebugSlotPolicy)
(def (yuanxu-debug-slot-policy label-value maximum-depth-value)
  (unless (> maximum-depth-value 0)
    (error "Yuanxu debug slot depth must be positive" maximum-depth-value))
  (validate YuanxuDebugSlotPolicyContract
    (.o (:: @ DebugSlotPolicy.)
        label: label-value
        maximum-depth: maximum-depth-value)))

;; : (-> YuanxuDebugSlotPolicy Symbol Symbol Natural [(Pair Symbol Symbol)] Symbol YuanxuDebugSlotReceipt)
(def (yuanxu-debug-slot-receipt policy receiver-value slot-value depth-value
                                  path-value outcome-value)
  (validate YuanxuDebugSlotPolicyContract policy)
  (let* ((policy-value policy)
         (accepted-value (memq outcome-value '(admitted resolved)))
         (reason-value
          (case outcome-value
            ((admitted) 'slot-resolution-admitted)
            ((resolved) 'slot-resolved)
            ((raised) 'slot-resolution-raised)
            ((rejected-cycle) 'recursive-slot-resolution)
            ((rejected-depth) 'maximum-slot-depth-exceeded)
            (else 'invalid-slot-outcome))))
    (validate YuanxuDebugSlotReceiptContract
      (.o (:: @ DebugSlotReceipt.)
          policy: policy-value
          receiver: receiver-value
          slot: slot-value
          depth: depth-value
          active-path: path-value
          outcome: outcome-value
          accepted?: (if accepted-value #t #f)
          reason: reason-value))))

;;; The slot renderer is a closed projection.  It cannot force or retain the
;;; receiver, computed value, resolver closure, or exception.
;; : (-> YuanxuDebugSlotReceipt Sexp)
(def (yuanxu-debug-slot-receipt-sexp receipt)
  (validate YuanxuDebugSlotReceiptContract receipt)
  (list 'debug-slot-observation
        (list 'label (.ref (.ref receipt 'policy) 'label))
        (list 'receiver (.ref receipt 'receiver))
        (list 'slot (.ref receipt 'slot))
        (list 'depth (.ref receipt 'depth))
        (list 'active-path (.ref receipt 'active-path))
        (list 'outcome (.ref receipt 'outcome))
        (list 'accepted? (.ref receipt 'accepted?))
        (list 'reason (.ref receipt 'reason))))

;;; Public policy construction remains POO-native. The defaults affect debug
;;; observation; the package test entrypoint applies the independent runtime
;;; heap profile before loading suites.
(def (yuanxu-debug-memory-policy label-value
                                   heap-limit-bytes: heap-limit-value
                                   live-growth-limit-bytes: live-growth-limit-value
                                   sample-interval-milliseconds:
                                   (sample-interval-value 100)
                                   collect-before-sample?: (collect-value #f)
                                   fail-closed?: (fail-closed-value #t))
  (validate YuanxuDebugMemoryPolicyContract
    (.o (:: @ DebugMemoryPolicy.)
        label: label-value
        heap-limit-bytes: heap-limit-value
        live-growth-limit-bytes: live-growth-limit-value
        sample-interval-milliseconds: sample-interval-value
        collect-before-sample?: collect-value
        fail-closed?: fail-closed-value)))

;;; At the runtime Case boundary, check the native POO shape owned by this
;;; constructor.  A compiled test batch may hold a distinct descriptor copy;
;;; descriptor identity is checked when the policy is constructed, while the
;;; resource-facing fields are checked again here before they are read.
(def (yuanxu-debug-memory-policy? value)
  (and (object? value)
       (.slot? value 'label)
       (symbol? (.ref value 'label))
       (.slot? value 'heap-limit-bytes)
       (exact-integer? (.ref value 'heap-limit-bytes))
       (>= (.ref value 'heap-limit-bytes) 0)
       (.slot? value 'live-growth-limit-bytes)
       (exact-integer? (.ref value 'live-growth-limit-bytes))
       (>= (.ref value 'live-growth-limit-bytes) 0)
       (.slot? value 'sample-interval-milliseconds)
       (exact-integer? (.ref value 'sample-interval-milliseconds))
       (> (.ref value 'sample-interval-milliseconds) 0)
       (.slot? value 'collect-before-sample?)
       (boolean? (.ref value 'collect-before-sample?))
       (.slot? value 'fail-closed?)
       (boolean? (.ref value 'fail-closed?))))

;;; The effectful adapter supplies already-read scalar counters here.
(def (yuanxu-debug-memory-sample phase-value heap-size-value allocated-value
                                   live-value movable-value still-value)
  (validate YuanxuDebugMemorySampleContract
    (.o (:: @ DebugMemorySample.)
        phase: phase-value
        heap-size-bytes: heap-size-value
        allocated-bytes: allocated-value
        live-bytes: live-value
        movable-bytes: movable-value
        still-bytes: still-value)))

(def (yuanxu-debug-memory-positive-delta after-value before-value)
  (max 0 (- after-value before-value)))

;;; This comparison is deterministic for equal policy and sample values. It
;;; does not read the clock, trigger collection, inspect the heap, or print.
(def (yuanxu-debug-memory-receipt policy before after)
  (validate YuanxuDebugMemoryPolicyContract policy)
  (validate YuanxuDebugMemorySampleContract before)
  (validate YuanxuDebugMemorySampleContract after)
  ;; The *-value bindings are semantically required: .o slot bodies use bare
  ;; slot names for self dispatch, so directly writing `policy: policy` would
  ;; create a recursive self.policy computation instead of capturing the
  ;; constructor argument.
  (let* ((policy-value policy)
         (before-value before)
         (after-value after)
         (phase-value (.ref after 'phase))
         (heap-growth
          (yuanxu-debug-memory-positive-delta
           (.ref after-value 'heap-size-bytes)
           (.ref before-value 'heap-size-bytes)))
         (live-growth
          (yuanxu-debug-memory-positive-delta
           (.ref after-value 'live-bytes)
           (.ref before-value 'live-bytes)))
         (heap-exceeded?
          (> (.ref after-value 'heap-size-bytes)
             (.ref policy-value 'heap-limit-bytes)))
         (growth-exceeded?
          (> live-growth (.ref policy-value 'live-growth-limit-bytes)))
         (reason-value
          (cond (heap-exceeded? 'heap-limit-exceeded)
                (growth-exceeded? 'live-growth-limit-exceeded)
                (else 'within-budget))))
    (validate YuanxuDebugMemoryReceiptContract
      (.o (:: @ DebugMemoryReceipt.)
          phase: phase-value
          policy: policy-value
          before: before-value
          after: after-value
          heap-growth-bytes: heap-growth
          live-growth-bytes: live-growth
          accepted?: (eq? reason-value 'within-budget)
          reason: reason-value))))

;;; Only bounded scalar diagnostics reach DDT or a terminal. The policy and raw
;;; samples remain available as native objects for local drill-down.
(def (yuanxu-debug-allocation-current? current? previous observed)
  ;; Once a native counter moves backwards, later increases cannot repair the
  ;; allocation evidence for that Case. Capacity/currentness gates are separate.
  (and current? (>= observed previous)))

(def (yuanxu-debug-memory-receipt-sexp receipt)
  (validate YuanxuDebugMemoryReceiptContract receipt)
  (list 'debug-memory-observation
        (list 'policy (.ref (.ref receipt 'policy) 'label))
        (list 'phase (.ref receipt 'phase))
        (list 'accepted? (.ref receipt 'accepted?))
        (list 'reason (.ref receipt 'reason))
        (list 'heap-size-bytes (.ref (.ref receipt 'after) 'heap-size-bytes))
        (list 'heap-growth-bytes (.ref receipt 'heap-growth-bytes))
        (list 'live-bytes (.ref (.ref receipt 'after) 'live-bytes))
        (list 'live-growth-bytes (.ref receipt 'live-growth-bytes))
        (list 'allocated-bytes (.ref (.ref receipt 'after) 'allocated-bytes))
        (list 'movable-bytes (.ref (.ref receipt 'after) 'movable-bytes))
        (list 'still-bytes (.ref (.ref receipt 'after) 'still-bytes))))
