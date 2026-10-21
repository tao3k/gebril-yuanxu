;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/profile-composition/selection-syntax use-module)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export ops-module-publication-test)
(def core-root (path-expand ".." (path-directory (this-source-file))))
(def (write-init path (disabled? #f))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (out)
      (write `(yuanxu! mode: explicit source: ,(path-expand "modules" core-root)
                (ops @ ,(path-expand "ops" core-root) disable: ,disabled?)) out))))
(def ops-module-publication-test
  (test-suite "Ops uses the admitted Core Module publication"
    (yuanxu-test-case "Core init selects Ops; loading and binding do not execute operations"
      (let* ((view (yuanxu-load-modules (path-expand "init.ss" core-root)))
             (Scope (.get view modules Modules ops)))
        (check-equal? (and (memq 'ops (.get view selected-graph module-order)) #t) #t)
        (check-equal? (.slot? Scope 'types) #t)
        ;; Selection, not a retained root, discovers every role and helper once.
        (for-each
          (lambda (name)
            (let (expected (path-normalize (path-expand name (path-expand "ops" core-root))))
              (check-equal?
                (length (filter (lambda (entry)
                                  (equal? (path-normalize (.get entry path)) expected))
                                (.get view build-graph entries))) 1)))
          '("types.ss" "config.ss" "func.ss" "objects.ss" "interface.ss" "selected-packages.ss"))
        ;; The published default has no command: eager .run would fail admission.
        (check-equal? (.get Scope prototypes Script command) '())
        (call-with-temporary-directory "ops-selected"
          (lambda (directory)
            (let* ((marker (path-expand "started" directory))
                   (Operation
                    (use-module Scope as ops
                      (.o (:: @ (.get ops prototypes Script))
                        command: (list "touch" marker)))))
              (check-equal? (procedure? (.get Operation .run)) #t)
              (check-equal? (file-exists? marker) #f)
              (check-equal? (.get (.call Operation .run) status) 0)
              (check-equal? (file-exists? marker) #t))))))
    (yuanxu-test-case "scope defaults remain receiver-local after a parent prototype is cached"
      (let* ((view (yuanxu-load-modules (path-expand "init.ss" core-root)))
             (Scope (.get view modules Modules ops))
             (parent (.get Scope prototypes Script))
             (Derived (.cc Scope 'config (.cc (.get Scope config) 'timeout 0.25 'check-status #f))))
        (check-equal? (.get parent timeout) #f)
        (check-equal? (.get Derived prototypes Script timeout) 0.25)
        (check-equal? (.get Derived prototypes Script check-status) #f)
        (check-equal? (.get parent timeout) #f)
        (check-equal? (.get parent check-status) #t)))
    (yuanxu-test-case "disabled selection and stale declaration cannot yield a current scope"
      (call-with-temporary-directory "ops-init"
        (lambda (directory)
          (let (init (path-expand "init.ss" directory))
            (write-init init)
            (let* ((view (yuanxu-load-modules init))
                   (scope (.get view modules ops)))
              (check-equal? (object? scope) #t)
              ((.get view admit-current))
              (call-with-output-file (list path: init append: #t)
                (cut display "\n;; changed selection source\n" <>))
              (check-exception ((.get view admit-current)) error?))
            (write-init init #t)
            (let (view (yuanxu-load-modules init))
              (check-equal? (memq 'ops (.get view selected-graph module-order)) #f)
              (check-equal? (.slot? (.get view modules) 'ops) #f))))))))
