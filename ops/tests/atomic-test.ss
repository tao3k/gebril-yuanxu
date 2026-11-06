;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Ops-only controls: no selected product/configuration Graph or Nix process.
(import :std/test :clan/poo/object
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/ops/func prepare-script-command)
        (only-in :yuanxu/ops/progress current-execution-progress current-execution-progress-port call-with-execution-progress
                 execution-progress! execution-progress-status progress-record)
        (only-in :yuanxu/observability/testing-fixture call-with-yuanxu-fixture)
        (only-in :std/error Error? Error-message Error-irritants))
(export ops-watchdog-test)
(def ops-watchdog-test
  (test-suite "Ops watchdog diagnostics and cleanup"
    (test-case "a separate report port retains the original watchdog frame"
      (def clock 0)
      (def report (open-output-string))
      (def console (open-output-string))
      (parameterize ((current-execution-progress '())
                     (current-execution-progress-port report)
                     (current-error-port console))
        (call-with-execution-progress 2000 6000
          (lambda (state)
            (set! clock 1000)
            (check-equal? (execution-progress! 'source-written 1) #t)
            (set! clock 1500)
            (check-equal? (execution-progress! 'source-written 1) #f)
            (set! clock 3000)
            (check-equal? (execution-progress-status state) 'idle))
          clock: (lambda () clock)))
      (check-equal? (get-output-string console) "")
      (def record
        (call-with-input-string (get-output-string report)
          (lambda (port)
            (check-equal? (read-line port) "")
            (def frame (progress-record (read-line port) "@yuanxu-progress "))
            (check-equal? (eof-object? (read-line port)) #t)
            frame)))
      (check-equal? (vector-ref record 1) 1))
    (test-case "prepared command retains the configured deadline and signal policy"
      (.def (Script @ ProcessScript.) command: '("printf" "ok") timeout: 2)
      (check-equal? (prepare-script-command Script)
        '("timeout" "--verbose" "--signal=TERM" "--kill-after=5s" "2s" "printf" "ok")))
    (test-case "a successful command has no watchdog diagnostic noise"
      (.def (Script @ ProcessScript.) command: '("printf" "ok") timeout: 2)
      (check-equal? (.get (.call Script .run) output) "ok"))
    (test-case "a supervised exchange transfers raw bytes and waits for exit"
      (.def (Script @ ProcessScript.) command: '("cat") timeout: 2)
      (def bytes '#u8(0 255 1))
      (def result
        (.call Script .with-process
          (lambda (port)
            (write-subu8vector bytes 0 3 port)
            (force-output port)
            (def received (make-u8vector 3))
            (check-equal? (read-subu8vector received 0 3 port) 3)
            (check-equal? received bytes)
            'complete)))
      (check-equal? result 'complete)
      (check-exception
        (.call (.cc Script command: '("false")) .with-process (lambda (_port) 'unpublished))
        (lambda (exception)
          (and (Error? exception)
               (string=? (Error-message exception) "Ops script failed")
               (equal? (Error-irritants exception) '(1 #f ""))))))
    (test-case "deadline refusal retains the watchdog's own signal evidence and releases the fixture"
      (def released? #f)
      (.def Fixture .acquire: (lambda () 'resource)
        .release: (lambda (resource)
                    (check-equal? resource 'resource)
                    (set! released? #t)))
      (.def (Script @ ProcessScript.) command: '("sleep" "5") timeout: 0.1)
      (check-exception
        (call-with-yuanxu-fixture Fixture (lambda (_resource) (.call Script .run)))
        (lambda (exception)
          (and (Error? exception)
               (string=? (Error-message exception) "Ops script failed")
               (let (details (Error-irritants exception))
                 (and (= (car details) 124)
                      (string-contains (caddr details) "sending signal TERM") #t)))))
      (check-equal? released? #t))))
