;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./prepare.ss")
(export prepare-test)

(def prepare-test
  (test-suite "Native Scheme qualification preparation"
    (test-case "extract reviewed Scheme into an explicit private fixture directory"
      (def destination (getenv "CONTRACT_FIXTURE_DIR"))
      (unless destination
        (error "Set CONTRACT_FIXTURE_DIR to the isolated fixture directory"))
      (prepare-contract-fixture
        (path-expand "docs/10-19-design/12-contracts-types/12.03-object-contract-schema-adapters-and-aws-admission.org")
        destination)
      (copy-contract-test-sources
        (path-expand "t/qualification/contract-adaptation") destination)
      (check-equal? (file-exists? (path-expand "fixture-schema.ss" destination)) #t)
      (check-equal? (file-exists? (path-expand "fixture-core.ss" destination)) #t)
      (check-equal? (file-exists? (path-expand "evidence-binding-test.ss" destination)) #t)
      (check-equal? (file-exists? (path-expand "generic-test.ss" destination)) #t))))
