;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Atomic adapter to the installed Gerbil test tool; no test execution model.
(import (rename-in (only-in :gerbil/tools/gxtest main) (main gerbil-test-main))
        (only-in :std/os/pid getpid)
        (only-in :yuanxu/ops/progress
                 call-with-execution-watchdog execution-idle-seconds
                 current-execution-progress-port))
(export main)

(def (main . arguments)
  (displayln "test-entry pid=" (getpid))
  (force-output)
  ;; Pass official CLI arguments unchanged. The tool owns import, module hooks,
  ;; std/test discovery and every assertion. Never demand init or build here.
  ;; Just owns the invocation's total process fence; Case policies own their
  ;; semantic limits. Do not add a second, conflicting aggregate deadline.
  (def (run)
    (call-with-execution-watchdog (* 1000 execution-idle-seconds) #f
      (lambda () (apply gerbil-test-main arguments))))
  (def report (getenv "YUANXU_TEST_REPORT_DIR" ""))
  (def status (if (string-empty? report) (run) (report-harness report arguments run)))
  (unless (eqv? status 0)
    ;; Preserve the official Harness status for callers such as mutation gates.
    ;; An import or compiler exception retains its distinct runtime failure.
    (exit status)))

(def (report-harness directory arguments run)
  (create-directory* directory)
  (def stem
    (path-expand (string-append (number->string (getpid)) "-"
                               (symbol->string (gensym 'harness)))
                 directory))
  (def progress-file (string-append stem ".progress"))
  (def receipt-file (string-append stem ".ss"))
  ;; The CLI can exit the process itself. Record its exact argv before entering;
  ;; the supervising process owns completion, clocks and exit status.
  (dynamic-wind
    (lambda () (setenv "YUANXU_TEST_REPORT_DIR" ""))
    (lambda ()
      (call-with-output-file progress-file
        (lambda (port)
          (call-with-output-file receipt-file
            (lambda (receipt)
              (write (list 'test-harness-start arguments progress-file) receipt)
              (newline receipt)))
          (parameterize ((current-execution-progress-port port)) (run)))))
    (lambda () (setenv "YUANXU_TEST_REPORT_DIR" directory))))
