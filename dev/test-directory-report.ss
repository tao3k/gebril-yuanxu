;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Observe the existing Just dispatch; Gerbil owns the Harness and verdict.
(import (only-in :clan/poo/object .o .cc .get)
        (only-in :std/io/tempfile make-temporary-file-name current-temporary-directory)
        (only-in :std/list/list delete-duplicates/hash take)
        (only-in :std/misc/process run-process)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/ops/process-script ProcessScript.))
(export main)

(def (elapsed-milliseconds started)
  (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second)))

(def (main group)
  ;; Just retains the discovery partition and the per-file preparation routes.
  ;; One Scheme observer owns the group, with one worker alive at a time.
  (def started (current-jiffy))
  (def files
    (filter (lambda (line) (not (string-empty? line)))
      (string-split (run-process (list "just" "test-files" group)) #\newline)))
  (unless (and (pair? files) (= (length files) (length (delete-duplicates/hash files))))
    (error "missing or duplicated files in the discovered test group" group))
  (def report (getenv "YUANXU_TEST_REPORT_DIR" ""))
  (when (string-empty? report) (set! report (make-temporary-file-name "yuanxu-test-report-")))
  (create-directory* report)
  (call-with-output-file (path-expand "expected-files.ss" report)
    (lambda (port) (write files port) (newline port)))
  (displayln "TEST-REPORT " report)
  (def outcomes '())
  (for-each
    (lambda (file)
      (defvalues (status wall) (report-dispatched-file report file))
      (set! outcomes (cons [file status wall] outcomes)))
    files)
  (def failed (map car (filter (lambda (row) (not (zero? (cadr row)))) (reverse outcomes))))
  (def elapsed (elapsed-milliseconds started))
  (call-with-output-file (path-expand "group.ss" report)
    (lambda (port)
      (write (list 'test-group-result group elapsed (reverse outcomes)) port)
      (newline port)))
  (displayln "TEST-GROUP-RESULT files=" (length files) " failed=" (length failed)
    " group-ms=" elapsed)
  (def slowest (list-sort (lambda (left right) (> (caddr left) (caddr right))) (reverse outcomes)))
  (for-each
    (lambda (row) (displayln "TEST-GROUP-SLOW " (car row) " dispatch-ms=" (caddr row)))
    (take slowest (min 5 (length slowest))))
  (for-each (lambda (file) (displayln "FAILED-TEST " file)) failed)
  (unless (null? failed) (exit 1)))

;; Measure the existing dispatch, including any special preparation selected
;; by Just. Assertions and Harness verdicts stay with the original worker.
(def (report-dispatched-file report file)
  (def directory
    (parameterize ((current-temporary-directory report))
      (make-temporary-file-name "dispatch-")))
  (create-directory directory)
  (def raw (path-expand "worker.log" directory))
  (def started (current-jiffy))
  (def entry #f)
  (def returned #f)
  (def module-line #f)
  (def harness-line #f)
  (def terminal? #f)
  (def phase #f)
  (def (observe line)
    (cond ((and (not entry) (string-prefix? "test-entry pid=" line))
           (set! entry (elapsed-milliseconds started)))
          ((string-prefix? "TEST-HARNESS-RESULT " line)
           (set! returned (elapsed-milliseconds started)))
          ((string-prefix? "MODULE-OK " line) (set! module-line line))
          ((string-prefix? "HARNESS-OK " line) (set! harness-line line))
          ((and harness-line (equal? line "OK\n")) (set! terminal? #t))
          ((or (string-prefix? "declaration-stage " line)
               (string-prefix? "runtime-capacity-start " line)
               (string-prefix? "runtime-phase-incomplete " line))
           (set! phase line))))
  (displayln "TEST-START " file)
  (force-output)
  (def result
    (run-script
      (.cc ProcessScript.
        command: (list "just" "test-discovered-file" file)
        environment: (.o YUANXU_TEST_REPORT_DIR: directory)
        log: raw check-status: #f progress: (lambda () observe))
      '() output-port: (current-output-port)))
  (def wall (elapsed-milliseconds started))
  (def status (.get result status))
  (def harness
    (filter (lambda (name) (string-suffix? ".ss" name)) (directory-files directory)))
  ;; A successful subprocess must also return a unique native Harness result.
  ;; The exact Harness argv is recorded by the child, including snapshot paths
  ;; and the existing AOT facade aliases.
  (def evidence
    (and (pair? harness) (null? (cdr harness))
         (call-with-input-file (path-expand (car harness) directory) read)))
  (def verified?
    (match evidence
      (['test-harness-result [path] 'passed 0 _ _]
       (and (expected-harness-file? file path)
            terminal? entry returned
            (equal? module-line (string-append "MODULE-OK " path "\n"))
            (equal? harness-line
                    (string-append "HARNESS-OK " (object->string [path]) "\n"))))
      (else #f)))
  (def row
    (list 'test-dispatch-result file 'exit-status status 'wait-status (.get result wait-status)
          'dispatch-ms wall 'entry-ms entry 'harness-return-ms returned
          'verified? verified? 'last-phase phase 'log raw 'harness evidence))
  (call-with-output-file (path-expand "dispatch.ss" directory)
    (lambda (port) (write row port) (newline port)))
  (display "TEST-DISPATCH-RESULT ") (write row) (newline) (force-output)
  (when (and (zero? status) (not verified?))
    (displayln "TEST-REPORT-FAIL missing successful Gerbil Harness receipt " file))
  (values (if (and (zero? status) (not verified?)) 1 status) wall))

(def (expected-harness-file? discovered actual)
  (case (string->symbol discovered)
    ((t/mop-store-boundary-test.ss)
     (equal? actual "t/mop-store-boundary-driver-test.ss"))
    ((t/source-admission-gateway-test.ss)
     (and (string-prefix? "/" actual)
          (string-suffix? (string-append "/source/yuanxu/" discovered) actual)))
    (else (equal? discovered actual))))
