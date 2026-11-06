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
    (error "official test harness failed" arguments status)))

(def (report-harness directory arguments run)
  (create-directory* directory)
  (def stem
    (path-expand (string-append (number->string (getpid)) "-"
                               (symbol->string (gensym 'harness)))
                 directory))
  (def progress-file (string-append stem ".progress"))
  (def receipt-file (string-append stem ".ss"))
  (def started (current-jiffy))
  (def failed? #f)
  (def cause #f)
  (def status
    (dynamic-wind
      ;; The CI report is owned by this Harness invocation. Any subprocess
      ;; supervised by Ops still relays machine frames on its ordinary port.
      (lambda () (setenv "YUANXU_TEST_REPORT_DIR" ""))
      (lambda ()
        (call-with-output-file progress-file
          (lambda (port)
            (parameterize ((current-execution-progress-port port))
              (with-catch
                (lambda (exception) (set! failed? #t) (set! cause exception) #f)
                run)))))
      (lambda () (setenv "YUANXU_TEST_REPORT_DIR" directory))))
  (def elapsed-ms
    (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second)))
  (def verdict (cond (failed? 'exception) ((eqv? status 0) 'passed) (else 'failed)))
  (with-catch
    (lambda (failure) (unless failed? (raise failure)))
    (lambda ()
      (call-with-output-file receipt-file
        (lambda (port)
          (write (list 'test-harness-result arguments verdict status elapsed-ms progress-file) port)
          (newline port)))
      (display "TEST-HARNESS-RESULT ")
      (write (list arguments verdict 'harness-status status 'harness-ms elapsed-ms))
      (newline)
      (force-output)))
  (if failed? (raise cause) status))
