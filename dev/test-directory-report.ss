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

(def (main action . arguments)
  (if (equal? action "--audit")
    (apply audit-report arguments)
    (begin
      (unless (null? arguments) (error "unexpected test group arguments" arguments))
      (report-group action))))

(def (discovered-files group)
  (filter (lambda (line) (not (string-empty? line)))
    (string-split (run-process (list "just" "test-files" group)) #\newline)))

(def (report-group group)
  ;; Just retains the discovery partition and the per-file preparation routes.
  ;; One Scheme observer owns the group, with one worker alive at a time.
  (def started (current-jiffy))
  (def files (discovered-files group))
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
      (write (list 'test-group-result group elapsed
               (map (lambda (key) (getenv key #f))
                    '("GITHUB_SHA" "GITHUB_RUN_ID" "GITHUB_RUN_ATTEMPT" "RUNNER_OS" "RUNNER_ARCH"))
               (reverse outcomes)) port)
      (newline port)))
  (displayln "TEST-GROUP-RESULT files=" (length files) " failed=" (length failed)
    " group-ms=" elapsed)
  (def slowest (list-sort (lambda (left right) (> (caddr left) (caddr right))) (reverse outcomes)))
  (for-each
    (lambda (row) (displayln "TEST-GROUP-SLOW " (car row) " dispatch-ms=" (caddr row)))
    (take slowest (min 5 (length slowest))))
  (for-each (lambda (file) (displayln "FAILED-TEST " file)) failed)
  (audit-report report group)
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
     (equal? actual "t/qualification/mop-state/store-boundary-driver.ss"))
    ((t/source-admission-gateway-test.ss)
     (and (string-prefix? "/" actual)
          (string-suffix? (string-append "/source/yuanxu/" discovered) actual)))
    (else (equal? discovered actual))))

;; Audit extracted artifacts without executing the data or a test worker.
(def (read-receipt path)
  (call-with-input-file path
    (lambda (port)
      (def value (read port))
      (unless (eof-object? (read port)) (error "multiple report records" path))
      value)))

(def (audit-dispatch directory)
  (def path (path-expand "dispatch.ss" directory))
  (match (read-receipt path)
    (['test-dispatch-result (? string? file) 'exit-status (? exact-integer? status)
      'wait-status (? exact-integer?) 'dispatch-ms (? exact-integer? wall)
      'entry-ms entry 'harness-return-ms returned 'verified? (? boolean? verified?)
      'last-phase _ 'log _ 'harness evidence]
     (unless (and (<= 0 status 255) (>= wall 0)
                  (or (not entry) (and (exact-integer? entry) (<= 0 entry wall)))
                  (or (not returned)
                      (and entry (exact-integer? returned) (<= entry returned wall)))
                  (file-exists? (path-expand "worker.log" directory)))
       (error "invalid worker timing or missing transcript" path))
     (when verified?
       (unless (match evidence
                 (['test-harness-result [actual] 'passed 0 _ progress]
                  (and entry returned (expected-harness-file? file actual)
                       (file-exists? (path-expand (path-strip-directory progress) directory))))
                 (else #f))
         (error "verified dispatch has no matching Harness evidence" path)))
     [file (if (and (zero? status) (not verified?)) 1 status) wall])
    (else (error "malformed dispatch receipt" path))))

(def (audit-group directory)
  (def report
    (if (file-exists? (path-expand "group.ss" directory)) directory
      (path-expand "test-report" directory)))
  (match (read-receipt (path-expand "group.ss" report))
    (['test-group-result (? string? group) (? exact-integer? elapsed) cohort rows]
     (def expected (discovered-files group))
     (def actual
       (filter-map
         (lambda (name)
           (and (string-prefix? "dispatch-" name)
                (audit-dispatch (path-expand name report))))
         (directory-files report)))
     (def (order rows)
       (list-sort (lambda (left right) (string<? (car left) (car right))) rows))
     (unless (and (list? cohort) (= (length cohort) 5)
                  (andmap (lambda (field) (or (not field) (string? field))) cohort)
                  (pair? expected) (equal? expected (read-receipt (path-expand "expected-files.ss" report)))
                  (equal? expected (map car rows)) (equal? (order rows) (order actual))
                  (>= elapsed (apply + (map caddr rows))))
       (error "incomplete or inconsistent test group coverage" group report))
     (values cohort rows))
    (else (error "malformed test group receipt" report))))

(def (audit-report root (group "all"))
  (def folders
    (if (or (file-exists? (path-expand "group.ss" root))
            (file-exists? (path-expand "test-report/group.ss" root)))
      [root] (map (cut path-expand <> root) (directory-files root))))
  (def cohort #f)
  (def rows '())
  (for-each
    (lambda (folder)
      (defvalues (identity results) (audit-group folder))
      (when (and cohort (not (equal? identity cohort)))
        (error "test reports mix CI runs, revisions, or platforms" folder))
      (set! cohort identity)
      (set! rows (append results rows)))
    folders)
  (unless (and (pair? rows) (equal? (list-sort string<? (map car rows)) (discovered-files group)))
    (error "incomplete or duplicate coverage across test groups" root group))
  (display "TEST-REPORT-AUDIT ")
  (write [group cohort (length rows)
           (length (filter (lambda (row) (not (zero? (cadr row)))) rows))])
  (newline))
