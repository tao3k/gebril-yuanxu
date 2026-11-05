;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(def assertions 0)
(def (check name result)
  (unless result (error "automatic-projection-control-failed" name))
  (set! assertions (+ assertions 1)))
(def (report name value) (write (list name value)) (newline) (force-output (current-output-port)))
(def pipeline-forces 0)
(def checks-forces 0)
(def unused-forces 0)
(def Root
  (.o (:: effective-config [])
    build: (.o commands: '("gerbil" "build"))
    test: (.o commands: '("gerbil" "env" "unit-tests.ss"))
    package: (.o commands: '("gerbil" "env" "package.ss"))
    unused:
    (begin (set! unused-forces (+ unused-forces 1))
           (.o commands: '("unused")))
    pipeline:
    (begin
      (set! pipeline-forces (+ pipeline-forces 1))
      (.o selected-checks: '(build test package)
          checks:
          (begin
            (set! checks-forces (+ checks-forces 1))
            (map (lambda (name) (.ref effective-config name)) selected-checks))))))
(def parent-pipeline (.get Root pipeline))
(def parent-checks (.get parent-pipeline checks))
(check 'parent-warmed (and (= pipeline-forces 1) (= checks-forces 1)))
(check 'parent-unused-lazy (= unused-forces 0))

;; Ordinary user declarations only: no reported/completed work list.
(.def (Release @ Root)
  build: =>.+ (.o commands: '("gerbil" "build" "--release"))
  smoke: (.o commands: '("printf" "smoke"))
  pipeline: =>.+ (.o selected-checks: '(build test package smoke)))
(check 'declaration-lazy
  (and (= pipeline-forces 1) (= checks-forces 1) (= unused-forces 0)))
(def (empty-obligations candidate context) '())
(def (final-identities? candidate)
  (let ((actual (.get candidate pipeline checks))
        (expected (map (lambda (name) (.ref candidate name))
                       (.get candidate pipeline selected-checks))))
    (and (= (length actual) (length expected)) (every eq? actual expected))))
(def (final-obligations candidate context)
  (if (and (eq? candidate (.get context target)) (final-identities? candidate))
    '() (list (.o kind: 'stale-final-checks))))
(def (receipt-ok? contract candidate context evidence)
  (and (yuanxu-validation-evidence? evidence)
       (yuanxu-validation-evidence-accepted? evidence)
       (eq? (.get evidence contract-identity) (.get contract identity))
       (eq? (.get evidence candidate) candidate)
       (eq? (.get evidence context) context)
       (eq? (.get evidence classification type-identity) (.get contract identity))
       (eq? (.get evidence classification candidate) candidate)
       (eq? (.get evidence classification context) context)))

;; Maintained upstream fixture Contracts. They validate data; commands never run.
(def (check-commands? candidate)
  (and (object? candidate) (.slot? candidate 'commands)
       (let ((commands (.get candidate commands)))
         (and (list? commands) (pair? commands) (every string? commands)))))
(def (check-command-obligations candidate context)
  (if (member "forbidden" (.get candidate commands))
    (list (.o kind: 'forbidden-command)) '()))
(def CheckPolicyContract
  (yuanxu-predicate-contract
    'projection/check-commands check-commands? check-command-obligations))
(def (build-obligations candidate context)
  (if (equal? (car (.get candidate commands)) "gerbil")
    (check-command-obligations candidate context)
    (list (.o kind: 'build-command-policy))))
(def BuildCheckContract
  (yuanxu-predicate-contract 'projection/build check-commands? build-obligations))
