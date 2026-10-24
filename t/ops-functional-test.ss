;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object (only-in :yuanxu/ops/interface Ops)
        (only-in :yuanxu/profile-composition/selection-syntax use-module)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export ops-functional-test)
;; Consume the Core publication directly; Ops has no OpenTofu fixture dependency.
(def ops-functional-test
  (test-suite "Ops Functional First uses the built-in Core scope"
    (yuanxu-test-case "pure validation, command preparation and preview create no effects"
      (use-module Ops as ops
        (with-slots (validate prepare-command preview) ops
          (call-with-temporary-directory "ops-preview"
            (lambda (root)
              (let* ((marker (path-expand "started" root)) (log (path-expand "output.log" root))
                     (Script (.cc (.get ops prototypes Script)
                               'command (list "touch" marker) 'log log 'timeout 2
                               'environment (.o KEEP: "override")))
                     (base (.o KEEP: "base" BASE_ONLY: "present"))
                     (expected (append '("timeout" "--verbose" "--signal=TERM" "--kill-after=5s" "2s")
                                       (list "touch" marker "literal $ argument")))
                     (view (preview Script '("literal $ argument") base)))
                (check-equal? (eq? (validate Script) Script) #t)
                (check-equal? (prepare-command Script '("literal $ argument")) expected)
                (check-equal? (.get view argv) expected)
                (check-equal? (.get view environment KEEP) "override")
                (check-equal? (.get view environment BASE_ONLY) "present")
                (check-equal? (.get base KEEP) "base")
                (check-equal? (.get (preview Script '("literal $ argument") base) argv) expected)
                (check-equal? (file-exists? marker) #f)
                (check-equal? (file-exists? log) #f)
                ;; A preview is an inspection value, not a second executable Script API.
                (check-exception (validate view) error?)
                (check-exception (preview (.cc Script 'command '("touch" 42))) error?)
                (check-exception (prepare-command Script '(42)) error?)))))))
    (yuanxu-test-case "environment merging has explicit inputs and leaves both unchanged"
      (use-module Ops as ops
        (with-slots (merge-environment preview) ops
          (let* ((base (.o KEEP: "base" BASE_ONLY: "a"))
                 (overrides (.o KEEP: "override" NEW: "b"))
                 (merged (merge-environment base overrides)))
            (check-equal? (.get merged KEEP) "override")
            (check-equal? (.get merged BASE_ONLY) "a")
            (check-equal? (.get merged NEW) "b")
            (check-equal? (.get base KEEP) "base")
            (check-equal? (.slot? base 'NEW) #f)
            (check-equal? (.slot? overrides 'BASE_ONLY) #f)
            (check-exception (merge-environment base (.o BAD: 42)) error?)
            (.def (Command @ (.get ops prototypes Script)) command: '("true"))
            ;; No host environment is sampled by the default preview.
            (check-equal? (.all-slots (.get (preview Command) environment)) '())))))
    (yuanxu-test-case "function and native method share execution, failures, logs and timeout"
      (use-module Ops as ops
        (with-slots (run) ops
          (call-with-temporary-directory "ops-functional-run"
            (lambda (root)
              (.def (Command @ (.get ops prototypes Script)) command: '("printf" "[%s]"))
              (check-equal? (.get (run Command '("literal $ argument")) output)
                            (.get (.call Command .run "literal $ argument") output))
              (.def (Timed @ Command) command: '("sleep" "5") timeout: 0.1
                check-status: #f log: (path-expand "timeout.log" root))
              (check-equal? (.get (run Timed) status) 124)
              (check-equal? (file-exists? (.get Timed log)) #t)
              (.def (Failed @ Command) command: (list "ls" (path-expand "missing" root))
                check-status: #f log: (path-expand "failed.log" root))
              (check-equal? (zero? (.get (run Failed) status)) #f)
              (check-exception (run (.cc Failed 'check-status #t)) error?)
              (check-equal? (string-empty? (call-with-input-file (.get Failed log) read-all-as-string)) #f))))))))
