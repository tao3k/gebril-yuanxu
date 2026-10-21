;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Ops-only controls: no selected product/configuration Graph or Nix process.
(import :std/test :clan/poo/object
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/ops/func prepare-script-command)
        (only-in :yuanxu/observability/testing-fixture call-with-yuanxu-fixture)
        (only-in :std/error Error? Error-message Error-irritants))
(export ops-watchdog-test)
(def ops-watchdog-test
  (test-suite "Ops watchdog diagnostics and cleanup"
    (test-case "prepared command retains the configured deadline and signal policy"
      (.def (Script @ ProcessScript.) command: '("printf" "ok") timeout: 2)
      (check-equal? (prepare-script-command Script)
        '("timeout" "--verbose" "--signal=TERM" "--kill-after=5s" "2s" "printf" "ok")))
    (test-case "a successful command has no watchdog diagnostic noise"
      (.def (Script @ ProcessScript.) command: '("printf" "ok") timeout: 2)
      (check-equal? (.get (.call Script .run) output) "ok"))
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
