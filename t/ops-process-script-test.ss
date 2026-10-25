;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object (only-in :yuanxu/ops/interface Ops)
        (only-in :yuanxu/ops/func run-script)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case
                 yuanxu-default-testing-case-profile)
        (only-in :yuanxu/observability/memory YuanxuDebugDurationAnomaly?)
        (only-in :std/os/signal kill)
        (only-in :std/os/error os-error? OSError-errno ESRCH)
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :std/misc/process run-process process-error?)
        (only-in :yuanxu/ops/progress copy-process-output))
(import (only-in "../ops/tests/atomic-test.ss" ops-watchdog-test))
(export ops-process-script-test ops-watchdog-test)
;; Consume the Core publication directly; Ops has no OpenTofu fixture dependency.
(def ProcessScript. (.get Ops prototypes Script))
(def (process-gone? pid)
  (with-catch
    (lambda (failure)
      (if (and (os-error? failure) (= (OSError-errno failure) ESRCH)) #t
        (raise failure)))
    (lambda () (kill pid 0) #f)))
(def ops-process-script-test
  (test-suite "POO declarative operational scripts"
    (yuanxu-test-case "line pump preserves callbacks, forwarding and final fragments"
      (def rows '())
      (def forwarded (open-output-string))
      (def captured
        (call-with-output-string
          (lambda (port)
            (run-process '("printf" "first\nlast") stdout-redirection: #t
              coprocess: (lambda (process)
                (copy-process-output process port
                  (lambda (row) (set! rows (cons row rows))) forwarded))))))
      (check-equal? captured "first\nlast")
      (check-equal? (get-output-string forwarded) captured)
      (check-equal? (reverse rows) '("first\n" "last")))
    (yuanxu-test-case "byte pump preserves undecodable output and forwards it"
      (def forwarded (open-output-u8vector))
      (def captured
        (call-with-output-u8vector
          (lambda (port)
            (run-process '("printf" "\\000\\377\\316\\273") stdout-redirection: #t
              coprocess: (lambda (process)
                (copy-process-output process port #f forwarded mode: 'bytes))))))
      (check-equal? captured #u8(0 255 206 187))
      (check-equal? (get-output-u8vector forwarded) captured))
    (yuanxu-test-case "text pump decodes split UTF-8 and propagates child failure"
      (check-equal?
        (call-with-output-string
          (lambda (port)
            (run-process '("sh" "-c" "printf '\\316'; sleep 0.02; printf '\\273'")
              stdout-redirection: #t
              coprocess: (lambda (process)
                (copy-process-output process port #f #f mode: 'text)))))
        "λ")
      (check-exception
        (call-with-output-string
          (lambda (port)
            (run-process '("sh" "-c" "printf failed; exit 17") stdout-redirection: #t
              coprocess: (lambda (process)
                (copy-process-output process port #f #f mode: 'text)))))
        process-error?))
    (yuanxu-test-case "invalid modes and chunk progress refuse before touching the child"
      (check-exception (copy-process-output #f #f #f #f mode: 'unknown) Error?)
      (check-exception (copy-process-output #f #f void #f mode: 'text) Error?)
      (check-exception (copy-process-output #f #f void #f mode: 'bytes) Error?))
    (yuanxu-test-case "Case cancellation terminates the owned Ops descendants"
      (call-with-temporary-directory "ops-cancel"
        (lambda (root)
          (def child-pid (path-expand "child.pid" root))
          (def program
            `(let ((child (open-process
                            '(path: "sleep" arguments: ("10")
                              stdin-redirection: #f stdout-redirection: #f))))
               (call-with-output-file ,child-pid
                 (lambda (port) (write (process-pid child) port)))
               (displayln "READY") (force-output)
               (thread-sleep! 10)))
          (def policy (.cc yuanxu-default-testing-case-profile
                         'max-duration-milliseconds 1000))
          (.def (Waiting @ ProcessScript.)
            command: (list "gxi" "-:max-heap=2G,debug=q" "-e" (object->string program))
            timeout: 10
            ;; Start the SAME one-second cancellation window only after the
            ;; real descendant exists. Slow interpreter startup is not cleanup.
            progress: (lambda ()
                        (lambda (line)
                          (when (string=? line "READY\n")
                            (.call policy .run policy "controlled Ops cancellation"
                              (lambda () (thread-sleep! 10)))))))
          (check-exception (.call Waiting .run) YuanxuDebugDurationAnomaly?)
          (check-equal? (file-exists? child-pid) #t)
          (def pid (call-with-input-file child-pid read))
          ;; Permit launchd to reap the killed orphan; never signal a PID read
          ;; from a file. Only execute-script signals its owned process group.
          (let wait ((remaining 100))
            (cond ((process-gone? pid) (check-equal? #t #t))
                  ((zero? remaining) (check-equal? (process-gone? pid) #t))
                  (else (thread-sleep! 0.01) (wait (- remaining 1))))))))
    (yuanxu-test-case "failed process retains captured diagnostic output"
      (call-with-temporary-directory "ops-failure-output"
        (lambda (root)
          (.def (Failure @ ProcessScript.)
            command: (list "ls" (path-expand "missing-output-probe" root)))
          (check-exception (.call Failure .run)
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception) "Ops script failed")
                   (let (details (Error-irritants exception))
                     (and (= (length details) 3)
                          (not (zero? (car details)))
                          (not (cadr details))
                          (string-contains (caddr details) "missing-output-probe") #t))))))))
    (yuanxu-test-case "machine stdout decoding can keep diagnostic stderr separate"
      (call-with-temporary-directory "ops-stderr"
        (lambda (workspace)
          (.def (Failure @ ProcessScript.)
            command: (list "ls" (path-expand "missing" workspace)) check-status: #f)
          (check-equal? (string-empty? (.get (run-script Failure) output)) #f)
          (check-equal? (.get (run-script Failure stderr-redirection: #f) output) ""))))
    (yuanxu-test-case "argv is literal, inheritance uses the effective receiver, imports execute nothing"
      (.def (Original @ ProcessScript.) command: '("printf" "%s"))
      (.def (Derived @ Original) command: '("printf" "[%s]"))
      (check-equal? (.get (.call Original .run "$(not-a-shell); spaced") output) "$(not-a-shell); spaced")
      (check-equal? (.get (.call Derived .run "value") output) "[value]")
      (check-equal? (.get (.call Original .run "value") output) "value")
      (check-equal? (.get Original timeout) (.get Ops config timeout)))
    (yuanxu-test-case "declaring and resolving an operation is inert; only invocation starts it"
      (call-with-temporary-directory "ops-inert"
        (lambda (root)
          (let (marker (path-expand "started" root))
            (.def (Operation @ ProcessScript.) command: (list "touch" marker))
            (check-equal? (file-exists? marker) #f)
            (check-equal? (procedure? (.get Operation .run)) #t)
            (check-equal? (file-exists? marker) #f)
            (check-equal? (.get (.call Operation .run) status) 0)
            (check-equal? (file-exists? marker) #t)))))
    (yuanxu-test-case "environment overlays and working directory remain explicit"
      (call-with-temporary-directory "ops-script"
        (lambda (root)
          (.def (Env @ ProcessScript.) command: '("printenv" "YUANXU_OPS_PROBE")
            environment: (.o YUANXU_OPS_PROBE: "literal $ value"))
          (check-equal? (.get (.call Env .run) output) "literal $ value\n")
          (check-equal? (getenv "YUANXU_OPS_PROBE" #f) #f)
          (.def (Directory @ ProcessScript.) command: '("pwd") directory: root)
          (let (output (.get (.call Directory .run) output))
            (check-equal? (path-normalize (substring output 0 (- (string-length output) 1)))
                          (path-normalize root))))))
    (yuanxu-test-case "status, timeout and streamed failure logs are retained"
      (call-with-temporary-directory "ops-script-log"
        (lambda (root)
          (.def (Failure @ ProcessScript.) command: '("false") check-status: #f)
          (check-equal? (.get (.call Failure .run) status) 1)
          (check-exception (.call (.cc Failure 'check-status #t) .run) error?)
          (.def (Timed @ ProcessScript.) command: '("sleep" "5") timeout: 0.1 check-status: #f
            log: (path-expand "timeout.log" root))
          (check-equal? (.get (.call Timed .run) status) 124)
          (check-equal? (and (string-contains
                             (call-with-input-file (.get Timed log) read-all-as-string)
                             "sending signal TERM") #t) #t)
          (check-equal? (file-exists? (.get Timed log)) #t)
          (.def (LoggedFailure @ ProcessScript.)
            command: (list "ls" (path-expand "missing-input" root))
            log: (path-expand "failure.log" root) check-status: #f)
          (check-equal? (zero? (.get (.call LoggedFailure .run) status)) #f)
          (check-equal? (file-exists? (.get LoggedFailure log)) #t)
          (check-equal? (string-empty? (call-with-input-file (.get LoggedFailure log) read-all-as-string)) #f)
          (check-exception (.call (.cc LoggedFailure 'check-status #t) .run) error?)
          (check-equal? (file-exists? (.get LoggedFailure log)) #t)
          (.def (Logged @ ProcessScript.) command: '("printf" "saved\n")
            log: (path-expand "output.log" root))
          (check-equal? (.get (.call Logged .run) status) 0)
          (check-equal? (call-with-input-file (.get Logged log) read-all-as-string) "saved\n")
          (check-exception (.call (.cc Logged 'command '("printf" 42)) .run) error?))))))
