;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: native POO observability Type/Contract scenario tests.

(export observability-feedback-test)

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         :std/test
        :yuanxu/observability/objects
        :yuanxu/observability/types
        (only-in :yuanxu/object-types/contracts
                 yuanxu-validation-evidence-accepted?))

(def (observability-test-ref row key)
  (cdr (assq key row)))

(def (observability-test-nested-ref row outer-key inner-key)
  (observability-test-ref (observability-test-ref row outer-key) inner-key))

(def (observability-sandbox-diagnostic severity)
  (yuanxu-observability-diagnostic-record
   severity 'contract 'sandbox-resource-validator 'build #f
   'permission-widening-denied
   "build cannot widen filesystem write scope"
   'author
   '((module . sandbox) (resource . filesystem))))

(def (observability-blocked-receipt diagnostic)
  (yuanxu-observability-feedback-receipt
   "yuanxu-observability-feedback/v1"
   'sandbox-resource
   (yuanxu-observability-graph
    'sandbox-resource '((nodes . (build)) (edges . ())))
   (list diagnostic)
   (yuanxu-observability-repair
    'author 'sandbox-resource-declaration '((field . filesystem)))
   (yuanxu-observability-readiness 'blocked #f)
   '((manifest-preview . #f))))

(def (observability-ready-receipt)
  (yuanxu-observability-feedback-receipt
   "yuanxu-observability-feedback/v1"
   'sandbox-resource
   (yuanxu-observability-graph
    'sandbox-resource
    '((nodes . (build)) (edges . ()))
    '((preview . ready)))
   '()
   (yuanxu-observability-repair #f #f)
   (yuanxu-observability-readiness 'ready #t)
   '((manifest-preview . report-only))))

(def observability-feedback-test
  (test-suite
   "native POO observability Type and Contract"

   (yuanxu-test-case "constructs a prototype-derived diagnostic and evidence"
     (let (diagnostic (observability-sandbox-diagnostic 'error))
       (check (yuanxu-observability-prototype?
               yuanxu-observability-receipt-prototype) => #t)
       (check (yuanxu-observability-diagnostic-contract? diagnostic) => #t)
       (check (yuanxu-validation-evidence-accepted?
               (yuanxu-observability-diagnostic-contract-evidence diagnostic))
              => #t)
       (check (yuanxu-observability-diagnostic-code diagnostic)
              => 'permission-widening-denied)))

   (yuanxu-test-case "rejects an invalid diagnostic obligation"
     (check-exception
      (observability-sandbox-diagnostic 'bad-severity)
      true))

   (yuanxu-test-case "projects blocked feedback from the admitted receipt"
     (let* ((receipt
             (observability-blocked-receipt
              (observability-sandbox-diagnostic 'error)))
            (feedback
             (yuanxu-observability-agent-feedback
              'yuanxu-agent-feedback
              'accept-sandbox-resource
              'repair-sandbox-resource
              receipt)))
       (check (yuanxu-observability-receipt-valid? receipt) => #f)
       (check (observability-test-ref feedback 'next-action)
              => 'repair-sandbox-resource)
       (check (observability-test-ref feedback 'family)
              => 'observability/receipt)
       (check (observability-test-nested-ref feedback 'graph 'kind)
              => 'sandbox-resource)
       (check (observability-test-nested-ref feedback 'repair 'target-layer)
              => 'author)
       (check (observability-test-nested-ref feedback 'readiness 'state)
              => 'blocked)
       (check (member 'permission-widening-denied
                      (observability-test-ref feedback 'diagnostic-codes))
              ? values)))

   (yuanxu-test-case "accepts ready feedback without diagnostics"
     (let* ((receipt (observability-ready-receipt))
            (feedback
             (yuanxu-observability-agent-feedback
              'yuanxu-agent-feedback
              'accept-sandbox-resource
              'repair-sandbox-resource
              receipt)))
       (check (yuanxu-observability-receipt-valid? receipt) => #t)
       (check (observability-test-ref feedback 'next-action)
              => 'accept-sandbox-resource)
       (check (observability-test-ref feedback 'diagnostic-codes) => '())))))
