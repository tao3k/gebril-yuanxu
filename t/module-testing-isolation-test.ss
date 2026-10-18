;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real source-only selection controls, separated from live init epoch tests.
(import "../init.ss" :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :core/module-system/building/test-projection module-test-file-source)
        (only-in :core/observability/testing-fixture with-poo-flow-fixture)
        (only-in :core/observability/testing-script TestingScript.)
        "./qualification/module-testing/fixtures.ss")
(export module-testing-isolation-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def (check-real-selection owner)
  (def scratch #f)
  (with-poo-flow-fixture (fixture (selection-fixture root))
    (set! scratch (path-normalize (path-expand "../.." (.get fixture root))))
    (prepare-selection! fixture root owner)
    (def other (if (eq? owner 'json-schema) "funflow" "json-schema"))
    (check-equal? (file-exists? (path-expand "lib/core" (.get fixture state))) #f)
    (.def (AtomicSelection @ TestingScript.)
      source: (module-test-file-source
                (list (path-expand "t/qualification/module-testing/selection-test.ss" (.get fixture root))))
      directory: (.get fixture root)
      environment: (.o GERBIL_PATH: (.get fixture state)
                       GERBIL_LOADPATH:
                       (string-append (path-expand "lib" (.get fixture state)) ":"
                                      (path-expand ".." (.get fixture root)))
                       CORE_TEST_SELECTION_OWNER: (symbol->string owner))
      timeout: 90)
    (.call AtomicSelection .run)
    (check-equal? (file-exists? (path-expand (string-append other ".scope") (.get fixture root))) #f)
    (check-equal? (file-exists? (path-expand (string-append other ".test") (.get fixture root))) #f))
  (check-equal? (file-exists? scratch) #f))
(def module-testing-isolation-test
  (test-suite "Real module source isolation"
    (test-case "JsonSchema-only init runs its real atomic suite without Funflow scope or tests"
      (check-real-selection 'json-schema))
    (test-case "Funflow-only init runs its real atomic suite without JsonSchema scope or tests"
      (check-real-selection 'funflow))))
