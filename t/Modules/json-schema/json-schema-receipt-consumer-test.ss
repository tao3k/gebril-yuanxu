;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Regression control for existing Core receipt consumers after owner separation.
(import :std/test
        :yuanxu/modules/json-schema/json-schema-receipt
        :yuanxu/modules/json-schema/json-schema-validate
        (only-in :yuanxu/modules/json-schema/json-schema-emit-runtime yuanxu-json-schema-null?))
(export json-schema-receipt-consumer-test)

(def json-schema-receipt-consumer-test
  (test-suite "Existing JsonSchema receipt consumer"
    (test-case "node diagnostics and receipt exports retain their structured identity"
      (def artifact
        (yuanxu-json-schema->contract-artifact
          '((type . "object") (properties . ((name . ((type . "string")))))
            (required . ("name")) (additionalProperties . #f))))
      (check-equal? (yuanxu-json-schema-contract-artifact-value-valid? artifact '((name . "api"))) #t)
      (check-equal? (yuanxu-json-schema-contract-artifact-value-valid? artifact '((name . 7))) #f)
      (def result (yuanxu-json-schema-contract-artifact-validate artifact '((name . 7))))
      (check-equal? (yuanxu-json-schema-object-contract-validation-valid? result) #f)
      (def issue (car (yuanxu-json-schema-object-contract-validation-diagnostics result)))
      (check-equal? (yuanxu-json-schema-validation-diagnostic? issue) #t)
      (check-equal? (pair? (yuanxu-json-schema-validation-diagnostic->alist issue)) #t)
      (check-equal? (yuanxu-json-schema-null? 'json-null) #t))))
