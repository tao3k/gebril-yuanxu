;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Actual dispatch work and admission-boundary controls; no cache or runner.
(import :std/test
        (only-in :clan/poo/object .o .get .ref .cc .put!)
        (only-in :clan/poo/slot-observation
                 call-with-slot-read-observer slot-read-key slot-read-receiver)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/module-system/source/interface yuanxu-module-interface)
        (only-in :yuanxu/module-system/authoring/admission
                 ModuleAuthoringAdmissionGeneric ModuleAuthoringAdmissionProtocol
                 yuanxu-module-authoring-role
                 yuanxu-module-authoring-admit-datums
                 yuanxu-module-authoring-admission-accepted?)
        (only-in :yuanxu/poo-clos/types
                 ClosGenericFunction ClosEffectiveMethod ClosInvocationFrame ClosMethod)
        (only-in :yuanxu/poo-clos/objects %prepare-effective-method)
        (only-in :yuanxu/poo-clos/dispatch
                 poo-clos-call poo-clos-compute-effective-method))
(export module-authoring-dispatch-work-test)

;; Count native policy-slot deliveries, including replay. This deliberately
;; does NOT call them predicate executions, allocations or elapsed work.
(def policies
  (list ClosGenericFunction ClosEffectiveMethod ClosInvocationFrame ClosMethod))
(def (policy-deliveries interface count)
  (def counts (make-vector (length policies) 0))
  (call-with-slot-read-observer
    (lambda (read)
      (when (eq? (slot-read-key read) '.element?)
        (let loop ((remaining policies) (index 0))
          (when (pair? remaining)
            (if (eq? (car remaining) (slot-read-receiver read))
              (vector-set! counts index (+ 1 (vector-ref counts index)))
              (loop (cdr remaining) (+ index 1)))))))
    (lambda ()
      (check-equal?
        (yuanxu-module-authoring-admission-accepted?
          (yuanxu-module-authoring-admit-datums
            interface 'objects (make-list count '(def value 1))))
        #t)))
  counts)

(def module-authoring-dispatch-work-test
  (test-suite "Actual authoring dispatch policy work"
    (yuanxu-test-case "warm datum admission still reads nested carrier policies"
      (def interface (yuanxu-module-interface "work-probe" (.o) '()))
      ;; Warm only through the actual operation; never clear or replace SDK state.
      (policy-deliveries interface 1)
      (def one (policy-deliveries interface 1))
      (def four (policy-deliveries interface 4))
      (def eight (policy-deliveries interface 8))
      (for-each
        (lambda (index)
          (check-equal? (> (vector-ref one index) 0) #t)
          (check-equal? (vector-ref four index) (* 4 (vector-ref one index)))
          (check-equal? (vector-ref eight index) (* 8 (vector-ref one index))))
        (iota (length policies)))
      (yuanxu-write-observation-line!
        "authoring-policy-deliveries order=generic,effective,frame,method one=%s four=%s eight=%s"
        one four eight))
    (yuanxu-test-case "closed default checks once and an open hook checks before and after"
      (def interface (yuanxu-module-interface "boundary-probe" (.o) '()))
      (def executor (.get interface authoring executor))
      (def role (yuanxu-module-authoring-role interface 'objects))
      (def checks 0)
      (def calls 0)
      (def protocol
        (.cc ModuleAuthoringAdmissionProtocol
          compute-effective-method:
          (lambda (_generic _arguments _methods checked-default)
            ;; This is a passive observation of the actual policy, not a
            ;; replacement validator or a new acceptance mechanism.
            (check-equal? checks 1)
            (set! calls (+ calls 1))
            checked-default)))
      (def open-generic
        (.cc ModuleAuthoringAdmissionGeneric protocol: protocol
          methods: (.get ModuleAuthoringAdmissionGeneric methods)))
      (def (observe read)
        (when (and (eq? (slot-read-receiver read) ClosEffectiveMethod)
                   (eq? (slot-read-key read) '.element?))
          (set! checks (+ 1 checks))))
      (call-with-slot-read-observer observe
        (lambda ()
          (poo-clos-compute-effective-method ModuleAuthoringAdmissionGeneric
            executor role interface '(def value 1))))
      (check-equal? checks 1)
      (set! checks 0)
      (call-with-slot-read-observer observe
        (lambda ()
          (poo-clos-compute-effective-method open-generic
            executor role interface '(def value 1))))
      (check-equal? checks 2)
      (check-equal? calls 1))
    (yuanxu-test-case "a prepared constructor produces a fresh checked carrier on each demand"
      (def interface (yuanxu-module-interface "fresh-carrier" (.o) '()))
      (def arguments
        (list (.get interface authoring executor)
          (yuanxu-module-authoring-role interface 'objects)
          interface '(def value 1)))
      (def effective
        (apply poo-clos-compute-effective-method ModuleAuthoringAdmissionGeneric arguments))
      (def prepare
        (%prepare-effective-method ModuleAuthoringAdmissionGeneric arguments
          (.get effective around) (.get effective before)
          (.get effective primary) (.get effective after)))
      (def first (prepare))
      (.put! first 'arguments #f)
      (def second (prepare))
      (check-equal? (eq? first second) #f)
      (check-equal? (eq? (.get second arguments) arguments) #t))
    (yuanxu-test-case "public effective-method callback may invalidate the checked default"
      (def interface (yuanxu-module-interface "callback-probe" (.o) '()))
      (def calls 0)
      (def protocol
        (.cc ModuleAuthoringAdmissionProtocol
          compute-effective-method:
          (lambda (_generic _arguments _methods checked-default)
            (set! calls (+ calls 1))
            ;; Negative injection at the real public hook boundary. The object
            ;; was checked at construction, but that check is now insufficient.
            (.put! checked-default 'arguments #f)
            checked-default)))
      ;; Native copying re-evaluates constructor slots; the registered method
      ;; set is runtime state, not the constructor's empty default. Retain the
      ;; actual descriptors explicitly in this private hook-injection probe.
      (def generic
        (.cc ModuleAuthoringAdmissionGeneric protocol: protocol
          methods: (.get ModuleAuthoringAdmissionGeneric methods)))
      (check-exception
        (poo-clos-call generic (.get interface authoring executor)
          (yuanxu-module-authoring-role interface 'objects)
          interface '(def value 1))
        (lambda (failure)
          (def code (.ref failure 'code))
          (yuanxu-write-observation-line! "authoring-return-probe code=%s calls=%s" code calls)
          (eq? code 'invalid-effective-method-result)))
      (check-equal? calls 1))))
