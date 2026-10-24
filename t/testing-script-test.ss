;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/observability/testing-script TestingScript. admit-testing-result
                 admit-testing-process-result make-compiler-progress-reader)
        (only-in :yuanxu/ops/progress call-with-execution-progress
                 execution-progress-idle-milliseconds))
(export testing-script-test)
;; Synthetic wire receipts exercise policy, not native-harness qualification.
(def files '("fixture-test.ss"))
(def valid-output "MODULE-OK fixture-test.ss\nHARNESS-OK (\"fixture-test.ss\")\nOK\n")
(def (receipt text (status-value 0)) (.o status: status-value output: text))
(def (synthetic-source (guard void)) (.o spec: files admit-current: guard))
(def testing-script-test
  (test-suite "Testing policy over Ops"
    (test-case "successive compilers advance one enclosing idle window independently"
      (def now 0)
      (call-with-execution-progress 60000 600000
        (lambda (state)
          (def first (make-compiler-progress-reader))
          (first "... compile prelude\n")
          (first "... execute compile job (compile-file prelude.scm)\n")
          (set! now 10000)
          (def next (make-compiler-progress-reader))
          ;; A rebuild's count=1 is real new work even after count=2 above.
          (next "... compile prelude\n")
          (check-equal? (execution-progress-idle-milliseconds state) 0)
          (set! now 10001)
          (next "ordinary diagnostic output\n")
          (check-equal? (execution-progress-idle-milliseconds state) 1)
          (set! now 20000)
          (def cleanup (make-compiler-progress-reader))
          ;; Native clean removes real products between the hot and rebuild
          ;; invocations. Its fresh count=1 is work, not an idle heartbeat.
          (cleanup "... remove lib/yuanxu/core-spec.ssi\n")
          (check-equal? (execution-progress-idle-milliseconds state) 0)
          (set! now 20001)
          (cleanup "clean completed\n")
          (check-equal? (execution-progress-idle-milliseconds state) 1))
        clock: (lambda () now)))
    (test-case "child VM follows the default two-GiB Case policy"
      (check-equal? (.get TestingScript. runtime-options)
                    '("-:max-heap=2097152K,debug=q")))
    (test-case "completion must match the whole native harness and every input"
      (def result (receipt valid-output))
      (check-equal? (eq? (admit-testing-result result files) result) #t)
      (for-each
        (lambda (text) (check-exception (admit-testing-result (receipt text) files) error?))
        (list "MODULE-OK fixture-test.ss\nOK\n"
              "HARNESS-OK (\"fixture-test.ss\")\nOK\n"
              "MODULE-OK fixture-test.ss\nHARNESS-OK (\"fixture-test.ss\")\n"
              "XMODULE-OK fixture-test.ss\nHARNESS-OK (\"fixture-test.ss\")\nOK\n"
              "MODULE-OK fixture-test.ss\nHARNESS-OK (\"other.ss\")\nOK\n"
              (string-append valid-output "ERROR CHECK deliberate\n")
              (string-append valid-output "ERROR MODULE deliberate\n")
              (string-append valid-output "ERROR CASE deliberate\n")
              (string-append valid-output "ERROR HARNESS deliberate\n")
              (string-append valid-output "Heap overflow\n")
              (string-append valid-output "Stack overflow\n")))
      (check-exception (admit-testing-result (receipt valid-output 1) files) error?)
      (check-exception (admit-testing-result result '("fixture-test.ss" "missing.ss")) error?)
      (check-exception (admit-testing-result result '()) error?))
    (test-case "one run brackets Ops; stale input rejects before command preparation"
      (def calls 0)
      (.def (Synthetic @ TestingScript.)
        source: (synthetic-source (lambda () (set! calls (+ calls 1))))
        command: (list "printf" "%s" valid-output))
      (check-equal? (.get (.call Synthetic .run) output) valid-output)
      (check-equal? calls 2)
      (def prepared? #f)
      (.def (Stale @ TestingScript.)
        source: (synthetic-source (lambda () (error "stale source")))
        command: (begin (set! prepared? #t) '("false")))
      (check-exception (.call Stale .run) error?)
      (check-equal? prepared? #f))
    (test-case "post-check rejects a zero-exit result when context changes"
      (def current #t)
      (def calls 0)
      (.def (Changed @ TestingScript.)
        source: (synthetic-source
                  (lambda () (set! calls (+ calls 1))
                    (unless current (error "context changed"))))
        command: (begin (set! current #f) (list "printf" "%s" valid-output)))
      (check-exception (.call Changed .run) error?)
      (check-equal? calls 2))
    (test-case "Ops failure still performs the post-check"
      (def calls 0)
      (.def (Failed @ TestingScript.)
        source: (synthetic-source (lambda () (set! calls (+ calls 1))))
        command: '("false"))
      (check-exception (.call Failed .run) error?)
      (check-equal? calls 2))
    (test-case "execution and post-check failures both retain their causes"
      (def calls 0)
      (def secondary (with-catch identity (lambda () (error "stale after execution"))))
      (.def (Both @ TestingScript.)
        source: (synthetic-source
                  (lambda () (set! calls (+ calls 1))
                    (when (= calls 2) (raise secondary))))
        command: '("false"))
      (check-exception (.call Both .run)
        (lambda (exception)
          (and (Error? exception)
               (let (causes (Error-irritants exception))
                 (and (= (length causes) 2)
                      (Error? (car causes))
                      (equal? (Error-message (car causes)) "Ops script failed")
                      (eq? (cadr causes) secondary))))))
      (check-equal? calls 2))
    (test-case "empty spec cannot trigger implicit directory discovery or a process"
      (def prepared? #f)
      (.def (Empty @ TestingScript.)
        source: (.o spec: '() admit-current: void)
        command: (begin (set! prepared? #t) '("false")))
      (check-exception (.call Empty .run) error?)
      (check-exception (.call (.cc Empty 'source files) .run) error?)
      (check-exception (.call (.cc Empty 'source (.o spec: files)) .run) error?)
      (check-equal? prepared? #f))
    (test-case "Ops log output receives the same admission"
      (call-with-temporary-directory "testing-script-"
        (lambda (workspace)
          (.def (Logged @ TestingScript.)
            source: (synthetic-source) command: (list "printf" "%s" valid-output)
            log: (path-expand "harness.log" workspace))
          (check-equal? (.get (.call Logged .run) output) valid-output))))
    (test-case "specialized admission remains inside the source Fixture"
      (def checks 0)
      (def admitted 0)
      (def specialized-output "MODULE-OK fixture-test.ss\nHARNESS-OK specialized\nOK\n")
      (.def (Specialized @ TestingScript.)
        source: (synthetic-source (lambda () (set! checks (+ checks 1))))
        command: (list "printf" "%s" specialized-output)
        .admit-result:
        (lambda (result)
          (set! admitted (+ admitted 1))
          (admit-testing-process-result result files)))
      (check-equal? (.get (.call Specialized .run) output) specialized-output)
      (check-equal? checks 2)
      (check-equal? admitted 1)
      ;; The ordinary native harness still requires its exact module list.
      (check-exception (admit-testing-result (receipt specialized-output) files) error?))
    (test-case "specialized receipt failure and final currentness failure both survive"
      (def checks 0)
      (def primary (with-catch values (lambda () (error "missing specialized receipt"))))
      (def secondary (with-catch values (lambda () (error "changed source"))))
      (.def (Specialized @ TestingScript.)
        source: (synthetic-source
                  (lambda ()
                    (set! checks (+ checks 1))
                    (when (= checks 2) (raise secondary))))
        command: (list "printf" "%s" valid-output)
        .admit-result: (lambda (_result) (raise primary)))
      (check-exception (.call Specialized .run)
        (lambda (failure)
          (and (Error? failure)
               (let (causes (Error-irritants failure))
                 (and (= (length causes) 2)
                      (eq? (car causes) primary) (eq? (cadr causes) secondary))))))
      (check-equal? checks 2))
    (test-case "cached parent admission does not capture a child's specialized policy"
      (def parent-calls 0)
      (def child-calls 0)
      (.def (Parent @ TestingScript.)
        source: (synthetic-source)
        command: (list "printf" "%s" valid-output)
        .admit-result:
        (lambda (result)
          (set! parent-calls (+ parent-calls 1))
          (admit-testing-result result files)))
      (.get Parent .admit-result)
      (.call Parent .run)
      (.def (Child @ Parent)
        .admit-result:
        (lambda (result)
          (set! child-calls (+ child-calls 1))
          (admit-testing-result result files)))
      (.call Child .run)
      (check-equal? parent-calls 1)
      (check-equal? child-calls 1))
    (test-case "common process admission never accepts error markers or incomplete output"
      (for-each
        (lambda (text)
          (check-exception (admit-testing-process-result (receipt text) files) error?))
        '("HARNESS-OK specialized\n" "OK\nERROR MODULE hidden\n" "OK\n*** ERROR hidden\n"))
      (check-exception (admit-testing-process-result (receipt "OK\n" 1) files) error?))
    (test-case "a specialized admission cannot bypass the common error gate"
      (def called? #f)
      (.def (Unchecked @ TestingScript.)
        source: (synthetic-source)
        command: '("printf" "OK\nERROR MODULE hidden\n")
        .admit-result: (lambda (result) (set! called? #t) result))
      (check-exception (.call Unchecked .run) error?)
      (check-equal? called? #f))
    (test-case "the installed gxi entry executes a real child harness exactly once"
      (call-with-temporary-directory "testing-launch-"
        (lambda (directory)
          (def counter (path-expand "executions" directory))
          (def file (path-normalize (path-expand "t/qualification/testing/launch-count-test.ss")))
          (.def (Driver @ TestingScript.)
            source: (.o spec: (list file) source-root: (current-directory) admit-current: void)
            command: (list "gxi" "-:max-heap=2G,debug=q"
                           "t/qualification/testing/run.ss" file
                           "-:max-heap=2G,debug=q" "60" "false")
            environment: (.o YUANXU_TEST_LAUNCH_COUNT: counter)
            profile: =>.+ (.o max-duration-milliseconds: 120000))
          (.call Driver .run)
          (check-equal? (call-with-input-file counter read-all-as-string) "launched\n"))))))
