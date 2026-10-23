;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; A real child-process invocation counter, owned by the enclosing test Fixture.
(import :std/test)
(export launch-count-test)
(def launch-count-test
  (test-suite "Native child launch count"
    (test-case "records one actual native harness execution"
      (call-with-output-file
        (list path: (getenv "YUANXU_TEST_LAUNCH_COUNT") append: #t)
        (lambda (port) (display "launched\n" port)))
      (check-equal? #t #t))))
