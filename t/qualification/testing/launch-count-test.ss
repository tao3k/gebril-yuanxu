;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Record the actual test VM, owned by the enclosing test Fixture.
(import :std/test (only-in :std/os/pid getpid))
(export launch-count-test)
(def launch-count-test
  (test-suite "Runtime child launch count"
    (test-case "records one official runtime harness execution"
      (call-with-output-file
        (list path: (getenv "YUANXU_TEST_LAUNCH_COUNT") append: #t)
        (lambda (port) (display (getpid) port) (newline port)))
      (check-equal? #t #t))))
