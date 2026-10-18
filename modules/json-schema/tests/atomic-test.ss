;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :core/modules/json-schema/func schema-contract)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/observability/testing-fixture poo-flow-test-fixture))
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
    (poo-flow-test-fixture "valid port and misspelled field use the real Schema adapter" (contract Contracts)
      (check-equal? (poo-flow-validation-evidence-accepted?
                     (poo-flow-contract-admit contract (.o port: 80) #f)) #t)
      (check-equal? (poo-flow-validation-evidence-accepted?
                     (poo-flow-contract-admit contract (.o prot: 80) #f)) #f))
    (poo-flow-test-case "boolean additionalProperties agrees for native and JSON objects"
      (for-each
        (lambda (allowed?)
          (def contract
            (schema-contract 'atomic/additional-properties
              `((type . "object") (additionalProperties . ,allowed?))))
          (for-each
            (lambda (candidate)
              (check-equal? (poo-flow-validation-evidence-accepted?
                             (poo-flow-contract-admit contract candidate #f)) allowed?))
            (list (.o extra: 42) '((extra . 42)))))
        '(#t #f)))))
