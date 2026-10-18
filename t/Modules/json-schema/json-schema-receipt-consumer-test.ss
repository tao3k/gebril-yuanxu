;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Regression control for existing Core receipt consumers after owner separation.
(import :std/test
        :core/modules/json-schema/json-schema-receipt
        :core/modules/json-schema/json-schema-validate
        (only-in :core/modules/json-schema/json-schema-emit-runtime poo-flow-json-schema-null?))
(export json-schema-receipt-consumer-test)

(def json-schema-receipt-consumer-test
  (test-suite "Existing JsonSchema receipt consumer"
    (test-case "node diagnostics and receipt exports retain their structured identity"
      (def artifact
        (poo-flow-json-schema->contract-artifact
          '((type . "object") (properties . ((name . ((type . "string")))))
            (required . ("name")) (additionalProperties . #f))))
      (check-equal? (poo-flow-json-schema-contract-artifact-value-valid? artifact '((name . "api"))) #t)
      (check-equal? (poo-flow-json-schema-contract-artifact-value-valid? artifact '((name . 7))) #f)
      (def result (poo-flow-json-schema-contract-artifact-validate artifact '((name . 7))))
      (check-equal? (poo-flow-json-schema-object-contract-validation-valid? result) #f)
      (def issue (car (poo-flow-json-schema-object-contract-validation-diagnostics result)))
      (check-equal? (poo-flow-json-schema-validation-diagnostic? issue) #t)
      (check-equal? (pair? (poo-flow-json-schema-validation-diagnostic->alist issue)) #t)
      (check-equal? (poo-flow-json-schema-null? 'json-null) #t))))
