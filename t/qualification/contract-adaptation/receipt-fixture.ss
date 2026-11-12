;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; TEST ONLY: an explicit immutable-context receipt, not Core admission.
(import :clan/poo/object :clan/poo/object-contract
        (prefix-in :clan/poo/declarative-metadata metadata.))
(export #t)

(def invocation-contract
  (metadata.contract
    (metadata.predicate "request" object?)
    (metadata.predicate "receipt" object?)
    (lambda (_atom _request _result) #t)
    metadata.truth))

(def (admit-fixture descriptor-value candidate-value view-value)
  (defvalues (receipt _state)
    (metadata.invoke invocation-contract
      (lambda (request)
        (let* ((value (.get request candidate))
               (constraint (.get request descriptor))
               (failures (diagnose constraint value '()))
               (result (.o candidate: value
                           descriptor: constraint
                           context: (.get request view)
                           issues: failures
                           accepted?: (null? failures))))
          (values result (.get request view))))
      (.o candidate: candidate-value
          descriptor: descriptor-value view: view-value)))
  receipt)

(def (fixture-current? receipt-value descriptor-value candidate-value view-value)
  (and (.get receipt-value accepted?)
       (eq? (.get receipt-value candidate) candidate-value)
       (eq? (.get receipt-value descriptor) descriptor-value)
       (eq? (.get receipt-value context) view-value)))
