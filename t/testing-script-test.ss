;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :core/observability/testing-script TestingScript. admit-testing-result))
(export testing-script-test)
;; Synthetic wire receipts exercise policy, not native-harness qualification.
(def files '("fixture-test.ss"))
(def valid-output "MODULE-OK fixture-test.ss\nHARNESS-OK (\"fixture-test.ss\")\nOK\n")
(def (receipt text (status-value 0)) (.o status: status-value output: text))
(def (synthetic-source (guard void)) (.o spec: files admit-current: guard))
(def testing-script-test
  (test-suite "Testing policy over Ops"
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
          (check-equal? (.get (.call Logged .run) output) valid-output))))))
