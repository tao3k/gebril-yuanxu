;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: explicit effectful DEVELOPMENT output over aggregate projections.
;;; Upstream owns tracing and typed printing. No global hook or tracer is copied.
(import :yuanxu/observability/memory
        (only-in :clan/poo/support/base λ)
        (only-in :clan/poo/object .o .call .ref)
        (only-in :clan/poo/mop validate)
        (only-in :clan/poo/support/debug traced-function)
        (only-in :clan/poo/debug DDT trace-poo)
        :gerbil/runtime/gambit
        (only-in :std/error deferror-class)
        (only-in :yuanxu/observability/types
                 YuanxuDebugMemoryPolicyContract
                 YuanxuDebugMemorySampleContract
                 YuanxuDebugMemoryReceiptContract
                 YuanxuDebugDurationReceiptContract
                 YuanxuDebugCallPolicyContract
                 YuanxuDebugCallReceiptContract)
        (only-in :yuanxu/observability/funcs yuanxu-observation-admission-summary
                 yuanxu-observation-summary-sexp
                 yuanxu-debug-call-policy
                 yuanxu-debug-call-receipt
                 yuanxu-debug-call-receipt-sexp
                 yuanxu-debug-memory-policy
                 yuanxu-debug-memory-policy?
                 yuanxu-debug-memory-sample
                 yuanxu-debug-memory-receipt
                 yuanxu-debug-memory-receipt-sexp)
        :yuanxu/observability/slot-debug)
(export yuanxu-observation-debug YuanxuObservationProjectionError?
        YuanxuDebugMemoryPolicyContract
        YuanxuDebugMemorySampleContract
        YuanxuDebugMemoryReceiptContract
        YuanxuDebugDurationReceiptContract
        YuanxuDebugCallPolicyContract
        YuanxuDebugCallReceiptContract
        yuanxu-debug-call-policy
        yuanxu-debug-call-receipt
        yuanxu-debug-call-receipt-sexp
        call-with-yuanxu-debug-trace
        YuanxuDebugCallAnomaly?
        YuanxuDebugCallAnomaly-receipt
        yuanxu-debug-memory-policy
        yuanxu-debug-memory-policy?
        yuanxu-debug-memory-sample
        yuanxu-debug-memory-receipt
        yuanxu-debug-memory-receipt-sexp
        yuanxu-debug-memory-snapshot
        yuanxu-debug-memory-checkpoint
        call-with-yuanxu-debug-memory-span
        call-with-yuanxu-debug-memory-monitor
        call-with-yuanxu-debug-memory-case-watchdog
        YuanxuDebugMemoryAnomaly?
        YuanxuDebugMemoryAnomaly-receipt
        YuanxuDebugDurationAnomaly?
        YuanxuDebugDurationAnomaly-receipt
        (import: :yuanxu/observability/slot-debug))

(deferror-class YuanxuObservationProjectionError ())
(deferror-class YuanxuDebugCallAnomaly (receipt))


;;; Active call identities are dynamic and thread-local.  The trace retains
;;; symbols only, so cycle/depth checks never keep user arguments or receivers.
;; : (Parameter [Symbol])
(def yuanxu-debug-active-call-path (make-parameter '()))

;; : (-> Integer Natural)
(def (yuanxu-debug-elapsed-nanoseconds started-jiffy)
  (quotient (* (- (current-jiffy) started-jiffy) 1000000000)
            (jiffies-per-second)))

;; : (-> Value Symbol)
(def (yuanxu-debug-operator-kind operator)
  (cond ((procedure? operator) 'procedure)
        ((pair? operator) 'pair)
        ((null? operator) 'null)
        ((symbol? operator) 'symbol)
        ((number? operator) 'number)
        ((string? operator) 'string)
        ((boolean? operator) 'boolean)
        (else 'other)))

;; : (-> YuanxuDebugCallReceipt OutputPort Unit)
(def (yuanxu-debug-emit-call-receipt receipt port)
  (parameterize ((current-error-port port))
    (DDT 'debug-call yuanxu-debug-call-receipt-sexp receipt)))

;; : (-> YuanxuDebugCallReceipt Never)
(def (yuanxu-debug-raise-call-anomaly receipt)
  (let (failure
        (YuanxuDebugCallAnomaly
         "Yuanxu debug call admission rejected the invocation"
         irritants: '()))
    (set! (YuanxuDebugCallAnomaly-receipt failure) receipt)
    (raise failure)))

;;; This is the bounded adapter over upstream `traced-function`.  Upstream sees
;;; a zero-argument thunk returning only the symbol `returned`; raw arguments,
;;; multiple results, and failures stay outside its printer.  Admission rejects
;;; a shadowed non-procedure and a recursive/deep call edge before invocation.
;; : (forall (a) (-> YuanxuDebugCallPolicy Symbol Value [Value] port: OutputPort emit?: Boolean a))
;; call-with-yuanxu-debug-trace
;;   : (-> YuanxuDebugCallPolicy Symbol Value [Value] port: OutputPort emit?: Boolean Object)
;;   | doc m%
;;       Admit and trace one bounded call edge while preserving the operator's
;;       returned values or original exception at the caller boundary.
;;       The specialized rejection branches run before invocation, and the
;;       upstream tracer receives only a closed zero-argument redacted thunk.
;;
;;       # Examples
;;
;;       ```scheme
;;       (call-with-yuanxu-debug-trace
;;        policy 'merge operator '(left right) emit?: #t)
;;       ;; => operator values, or raises a typed call anomaly
;;       ```
;;     %
(def (call-with-yuanxu-debug-trace policy call-id operator arguments
                                     port: (port (current-error-port))
                                     emit?: (emit? #t))
  (unless (and (symbol? call-id) (list? arguments)
               (output-port? port) (boolean? emit?))
    (error "invalid Yuanxu debug trace request" call-id))
  (unless (eq? (validate YuanxuDebugCallPolicyContract policy) policy)
    (error "invalid Yuanxu debug call policy"))
  (let* ((path (yuanxu-debug-active-call-path))
         (started-jiffy (current-jiffy))
         (depth (length path))
         (operator-kind (yuanxu-debug-operator-kind operator))
         (rejected-outcome
          (cond ((not (procedure? operator)) 'rejected-non-procedure)
                ((memq call-id path) 'rejected-cycle)
                ((>= depth (.ref policy 'maximum-depth)) 'rejected-depth)
                (else #f))))
    (when rejected-outcome
      (let (receipt
            (yuanxu-debug-call-receipt
             policy call-id depth path operator-kind rejected-outcome))
        (when emit? (yuanxu-debug-emit-call-receipt receipt port))
        (yuanxu-debug-raise-call-anomaly receipt)))
    (let ((result-values '())
          (admitted
           (yuanxu-debug-call-receipt
            policy call-id depth path operator-kind 'admitted)))
      (when emit? (yuanxu-debug-emit-call-receipt admitted port))
      (parameterize ((yuanxu-debug-active-call-path (cons call-id path)))
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
               (yuanxu-debug-emit-call-receipt
                (yuanxu-debug-call-receipt
                 policy call-id depth path operator-kind 'raised
                 (yuanxu-debug-elapsed-nanoseconds started-jiffy))
                port))
             (raise failure))
           (lambda ()
             (if emit?
               ((traced-function
                 (list 'yuanxu-debug-call call-id)
                 invoke
                 port))
               (invoke))))))
      (when emit?
        (yuanxu-debug-emit-call-receipt
         (yuanxu-debug-call-receipt
          policy call-id depth path operator-kind 'returned
          (yuanxu-debug-elapsed-nanoseconds started-jiffy))
         port))
      (apply values result-values))))

;; : (-> YuanxuDebugMemoryReceipt Never)
;; yuanxu-debug-raise-memory-anomaly
;;   : (-> YuanxuDebugMemoryReceipt Never)
;;   | doc m%
;;       Raise the typed fail-closed anomaly while retaining the exact rejected
;;       receipt for native Scheme handlers and audit projections.
;;       The specialized constructor path mutates only the exception's receipt
;;       field before raising and cannot substitute or recompute the evidence.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-debug-raise-memory-anomaly rejected-receipt)
;;       ;; => raises YuanxuDebugMemoryAnomaly with rejected-receipt
;;       ```
;;     %
;; : (-> YuanxuObservation YuanxuObservationSummary)
(def (yuanxu-observation-debug-summary observation)
  (with-exception-catcher
   (λ (_failure)
     ;; Do not attach the original exception/irritants: they may hold a subject.
     (raise (YuanxuObservationProjectionError "observation projection rejected")))
   (λ () (yuanxu-observation-admission-summary observation))))

;;; This entry point intentionally does not dispatch an arbitrary user .summary
;;; renderer. A fresh closed-schema aggregate is built before any output occurs.
;;; trace? traces only the aggregate view, never the observed Module receiver.
;; : (-> YuanxuObservation OutputPort trace?: Boolean YuanxuObservationSummary)
;; yuanxu-observation-debug
;;   : (-> YuanxuObservation OutputPort trace?: Boolean YuanxuObservationSummary)
;;   | doc m%
;;       Emit only the admitted closed-schema observation summary and return
;;       that identical native POO aggregate to the caller.
;;       The specialized trace branch constructs a fresh bounded view, so it
;;       cannot dispatch a renderer on the observed Module receiver.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-observation-debug observation (current-error-port) trace?: #f)
;;       ;; => YuanxuObservationSummary
;;       ```
;;     %
(def (yuanxu-observation-debug observation port trace?: (trace? #f))
  (unless (and (output-port? port) (boolean? trace?))
    (raise (YuanxuObservationProjectionError "invalid observation debug output request")))
  (let (summary (yuanxu-observation-debug-summary observation))
    (parameterize ((current-error-port port))
      (when trace?
        (let* ((view (.o (render (cut yuanxu-observation-summary-sexp summary))))
               (traced (trace-poo view 'admission-observation-view)))
          (.call traced render)))
      ;; Admission already validated the closed summary contract. DDT receives
      ;; only the pure presentation projection, so no dependency Type adapter is needed.
      (DDT 'observation yuanxu-observation-summary-sexp summary))
    summary))
