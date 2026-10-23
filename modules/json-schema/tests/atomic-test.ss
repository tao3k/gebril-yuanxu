;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :yuanxu/modules/json-schema/func schema-contract)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture))
(export json-schema-atomic-test)
(.def Contracts
  .acquire: (lambda ()
             (schema-contract 'atomic/port
               '((type . "object") (required . ("port"))
                 (additionalProperties . #f)
                 (properties . ((port . ((type . "integer") (minimum . 1))))))))
  .release: (lambda (_contract) (void)))
(def json-schema-atomic-test
  (test-suite "JsonSchema module atomic contracts"
    (yuanxu-test-fixture "valid port and misspelled field use the real Schema adapter" (contract Contracts)
      (check-equal? (yuanxu-validation-evidence-accepted?
                     (yuanxu-contract-admit contract (.o port: 80) #f)) #t)
      (check-equal? (yuanxu-validation-evidence-accepted?
                     (yuanxu-contract-admit contract (.o prot: 80) #f)) #f))
    (yuanxu-test-case "boolean additionalProperties agrees for native and JSON objects"
      (for-each
        (lambda (allowed?)
          (def contract
            (schema-contract 'atomic/additional-properties
              `((type . "object") (additionalProperties . ,allowed?))))
          (for-each
            (lambda (candidate)
              (check-equal? (yuanxu-validation-evidence-accepted?
                             (yuanxu-contract-admit contract candidate #f)) allowed?))
            (list (.o extra: 42) '((extra . 42)))))
        '(#t #f)))))
