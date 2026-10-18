;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: explicit effectful DEVELOPMENT output over aggregate projections.
;;; Upstream owns tracing and typed printing. No global hook or tracer is copied.
(import :core/observability/memory
        (only-in :clan/poo/support/base λ)
        (only-in :clan/poo/object .o .call .ref)
        (only-in :clan/poo/mop validate)
        (only-in :clan/poo/support/debug traced-function)
        (only-in :clan/poo/debug DDT trace-poo)
        :gerbil/runtime/gambit
        (only-in :std/error deferror-class)
        (only-in :core/observability/types
                 PooFlowDebugMemoryPolicyContract
                 PooFlowDebugMemorySampleContract
                 PooFlowDebugMemoryReceiptContract
                 PooFlowDebugDurationReceiptContract
                 PooFlowDebugCallPolicyContract
                 PooFlowDebugCallReceiptContract)
        (only-in :core/observability/funcs poo-flow-observation-admission-summary
                 poo-flow-observation-summary-sexp
                 poo-flow-debug-call-policy
                 poo-flow-debug-call-receipt
                 poo-flow-debug-call-receipt-sexp
                 poo-flow-debug-memory-policy
                 poo-flow-debug-memory-policy?
                 poo-flow-debug-memory-sample
                 poo-flow-debug-memory-receipt
                 poo-flow-debug-memory-receipt-sexp)
        :core/observability/slot-debug)
(export poo-flow-observation-debug PooFlowObservationProjectionError?
        PooFlowDebugMemoryPolicyContract
        PooFlowDebugMemorySampleContract
        PooFlowDebugMemoryReceiptContract
        PooFlowDebugDurationReceiptContract
        PooFlowDebugCallPolicyContract
        PooFlowDebugCallReceiptContract
        poo-flow-debug-call-policy
        poo-flow-debug-call-receipt
        poo-flow-debug-call-receipt-sexp
        call-with-poo-flow-debug-trace
        PooFlowDebugCallAnomaly?
        PooFlowDebugCallAnomaly-receipt
        poo-flow-debug-memory-policy
        poo-flow-debug-memory-policy?
        poo-flow-debug-memory-sample
        poo-flow-debug-memory-receipt
        poo-flow-debug-memory-receipt-sexp
        poo-flow-debug-memory-snapshot
        poo-flow-debug-memory-checkpoint
        call-with-poo-flow-debug-memory-span
        call-with-poo-flow-debug-memory-monitor
        call-with-poo-flow-debug-memory-case-watchdog
        PooFlowDebugMemoryAnomaly?
        PooFlowDebugMemoryAnomaly-receipt
        PooFlowDebugDurationAnomaly?
        PooFlowDebugDurationAnomaly-receipt
        (import: :core/observability/slot-debug))

(deferror-class PooFlowObservationProjectionError ())
(deferror-class PooFlowDebugCallAnomaly (receipt))


;;; Active call identities are dynamic and thread-local.  The trace retains
;;; symbols only, so cycle/depth checks never keep user arguments or receivers.
;; : (Parameter [Symbol])
(def poo-flow-debug-active-call-path (make-parameter '()))

;; : (-> Integer Natural)
(def (poo-flow-debug-elapsed-nanoseconds started-jiffy)
  (quotient (* (- (current-jiffy) started-jiffy) 1000000000)
            (jiffies-per-second)))

;; : (-> Value Symbol)
(def (poo-flow-debug-operator-kind operator)
  (cond ((procedure? operator) 'procedure)
        ((pair? operator) 'pair)
        ((null? operator) 'null)
        ((symbol? operator) 'symbol)
        ((number? operator) 'number)
        ((string? operator) 'string)
        ((boolean? operator) 'boolean)
        (else 'other)))

;; : (-> PooFlowDebugCallReceipt OutputPort Unit)
(def (poo-flow-debug-emit-call-receipt receipt port)
  (parameterize ((current-error-port port))
    (DDT 'debug-call poo-flow-debug-call-receipt-sexp receipt)))

;; : (-> PooFlowDebugCallReceipt Never)
(def (poo-flow-debug-raise-call-anomaly receipt)
  (let (failure
        (PooFlowDebugCallAnomaly
         "POO Flow debug call admission rejected the invocation"
         irritants: '()))
    (set! (PooFlowDebugCallAnomaly-receipt failure) receipt)
    (raise failure)))

;;; This is the bounded adapter over upstream `traced-function`.  Upstream sees
;;; a zero-argument thunk returning only the symbol `returned`; raw arguments,
;;; multiple results, and failures stay outside its printer.  Admission rejects
;;; a shadowed non-procedure and a recursive/deep call edge before invocation.
;; : (forall (a) (-> PooFlowDebugCallPolicy Symbol Value [Value] port: OutputPort emit?: Boolean a))
;; call-with-poo-flow-debug-trace
;;   : (-> PooFlowDebugCallPolicy Symbol Value [Value] port: OutputPort emit?: Boolean Object)
;;   | doc m%
;;       Admit and trace one bounded call edge while preserving the operator's
;;       returned values or original exception at the caller boundary.
;;       The specialized rejection branches run before invocation, and the
;;       upstream tracer receives only a closed zero-argument redacted thunk.
;;
;;       # Examples
;;
;;       ```scheme
;;       (call-with-poo-flow-debug-trace
;;        policy 'merge operator '(left right) emit?: #t)
;;       ;; => operator values, or raises a typed call anomaly
;;       ```
;;     %
(def (call-with-poo-flow-debug-trace policy call-id operator arguments
                                     port: (port (current-error-port))
                                     emit?: (emit? #t))
  (unless (and (symbol? call-id) (list? arguments)
               (output-port? port) (boolean? emit?))
    (error "invalid POO Flow debug trace request" call-id))
  (unless (eq? (validate PooFlowDebugCallPolicyContract policy) policy)
    (error "invalid POO Flow debug call policy"))
  (let* ((path (poo-flow-debug-active-call-path))
         (started-jiffy (current-jiffy))
         (depth (length path))
         (operator-kind (poo-flow-debug-operator-kind operator))
         (rejected-outcome
          (cond ((not (procedure? operator)) 'rejected-non-procedure)
                ((memq call-id path) 'rejected-cycle)
                ((>= depth (.ref policy 'maximum-depth)) 'rejected-depth)
                (else #f))))
    (when rejected-outcome
      (let (receipt
            (poo-flow-debug-call-receipt
             policy call-id depth path operator-kind rejected-outcome))
        (when emit? (poo-flow-debug-emit-call-receipt receipt port))
        (poo-flow-debug-raise-call-anomaly receipt)))
    (let ((result-values '())
          (admitted
           (poo-flow-debug-call-receipt
            policy call-id depth path operator-kind 'admitted)))
      (when emit? (poo-flow-debug-emit-call-receipt admitted port))
      (parameterize ((poo-flow-debug-active-call-path (cons call-id path)))
        (let ((invoke
               (lambda ()
                 (call-with-values
                   (lambda () (apply operator arguments))
                   (lambda captured-values
                     (set! result-values captured-values)
                     'returned)))))
          (with-exception-catcher
           (lambda (failure)
             (when emit?
               (poo-flow-debug-emit-call-receipt
                (poo-flow-debug-call-receipt
                 policy call-id depth path operator-kind 'raised
                 (poo-flow-debug-elapsed-nanoseconds started-jiffy))
                port))
             (raise failure))
           (lambda ()
             (if emit?
               ((traced-function
                 (list 'poo-flow-debug-call call-id)
                 invoke
                 port))
               (invoke))))))
      (when emit?
        (poo-flow-debug-emit-call-receipt
         (poo-flow-debug-call-receipt
          policy call-id depth path operator-kind 'returned
          (poo-flow-debug-elapsed-nanoseconds started-jiffy))
         port))
      (apply values result-values))))

;; : (-> PooFlowDebugMemoryReceipt Never)
;; poo-flow-debug-raise-memory-anomaly
;;   : (-> PooFlowDebugMemoryReceipt Never)
;;   | doc m%
;;       Raise the typed fail-closed anomaly while retaining the exact rejected
;;       receipt for native Scheme handlers and audit projections.
;;       The specialized constructor path mutates only the exception's receipt
;;       field before raising and cannot substitute or recompute the evidence.
;;
;;       # Examples
;;
;;       ```scheme
;;       (poo-flow-debug-raise-memory-anomaly rejected-receipt)
;;       ;; => raises PooFlowDebugMemoryAnomaly with rejected-receipt
;;       ```
;;     %
;; : (-> PooFlowObservation PooFlowObservationSummary)
(def (poo-flow-observation-debug-summary observation)
  (with-exception-catcher
   (λ (_failure)
     ;; Do not attach the original exception/irritants: they may hold a subject.
     (raise (PooFlowObservationProjectionError "observation projection rejected")))
   (λ () (poo-flow-observation-admission-summary observation))))

;;; This entry point intentionally does not dispatch an arbitrary user .summary
;;; renderer. A fresh closed-schema aggregate is built before any output occurs.
;;; trace? traces only the aggregate view, never the observed Module receiver.
;; : (-> PooFlowObservation OutputPort trace?: Boolean PooFlowObservationSummary)
;; poo-flow-observation-debug
;;   : (-> PooFlowObservation OutputPort trace?: Boolean PooFlowObservationSummary)
;;   | doc m%
;;       Emit only the admitted closed-schema observation summary and return
;;       that identical native POO aggregate to the caller.
;;       The specialized trace branch constructs a fresh bounded view, so it
;;       cannot dispatch a renderer on the observed Module receiver.
;;
;;       # Examples
;;
;;       ```scheme
;;       (poo-flow-observation-debug observation (current-error-port) trace?: #f)
;;       ;; => PooFlowObservationSummary
;;       ```
;;     %
(def (poo-flow-observation-debug observation port trace?: (trace? #f))
  (unless (and (output-port? port) (boolean? trace?))
    (raise (PooFlowObservationProjectionError "invalid observation debug output request")))
  (let (summary (poo-flow-observation-debug-summary observation))
    (parameterize ((current-error-port port))
      (when trace?
        (let* ((view (.o (render (cut poo-flow-observation-summary-sexp summary))))
               (traced (trace-poo view 'admission-observation-view)))
          (.call traced render)))
      ;; Admission already validated the closed summary contract. DDT receives
      ;; only the pure presentation projection, so no dependency Type adapter is needed.
      (DDT 'observation poo-flow-observation-summary-sexp summary))
    summary))
