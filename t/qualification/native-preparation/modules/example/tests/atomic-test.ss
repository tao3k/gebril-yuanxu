;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/source this-source-file)
        :yuanxu-native-preparation/modules/example/tests/shared)
(export atomic-test)

;; These effects distinguish Gerbil support compilation from actual Suite import
;; and Case execution. They are restored by the enclosing package Fixture.
(def root (path-expand "../../.." (path-directory (this-source-file))))
(call-with-output-file (path-expand "harness-started" root)
  (lambda (out) (display "native Harness import" out)))
(def atomic-test
  (test-suite "prepared native support"
    (test-case "compiled helper"
      (check-equal? answer 42)
      (call-with-output-file (path-expand "case-finished" root)
        (lambda (out) (display "native TestCase executed" out))))))
