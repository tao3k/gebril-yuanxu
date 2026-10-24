;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/ops/interface Ops)
        (only-in :yuanxu/ops/types OpsScopeContract)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/profile-composition/selection-syntax use-module)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export ops-module-publication-test)
(def core-root (path-expand ".." (path-directory (this-source-file))))
(def ops-module-publication-test
  (test-suite "Ops is a built-in Core library, independent of init selection"
    (yuanxu-test-case "importing and binding the built-in scope do not execute operations"
      (check-equal? (.get (.call OpsScopeContract .admit Ops #f) accepted?) #t)
      ;; The built-in default has no command: an eager .run would fail.
      (check-equal? (.get Ops prototypes Script command) '())
      (call-with-temporary-directory "ops-built-in"
        (lambda (directory)
          (let* ((marker (path-expand "started" directory))
                 (Operation
                   (use-module Ops as ops
                     (.o (:: @ (.get ops prototypes Script))
                       command: (list "touch" marker)))))
            (check-equal? (procedure? (.get Operation .run)) #t)
            (check-equal? (file-exists? marker) #f)
            (check-equal? (.get (.call Operation .run) status) 0)
            (check-equal? (file-exists? marker) #t)))))
    (yuanxu-test-case "cached parent defaults remain receiver-local"
      (def parent (.get Ops prototypes Script))
      (def Derived (.cc Ops 'config (.cc (.get Ops config) 'timeout 0.25 'check-status #f)))
      (check-equal? (.get parent timeout) #f)
      (check-equal? (.get Derived prototypes Script timeout) 0.25)
      (check-equal? (.get Derived prototypes Script check-status) #f)
      (check-equal? (.get parent timeout) #f)
      (check-equal? (.get parent check-status) #t))
    (yuanxu-test-case "Core selection omits Ops without changing declaration currentness"
      (def selected (yuanxu-load-modules (path-expand "init.ss" core-root)))
      (check-equal? (memq 'ops (.get selected selected-graph module-order)) #f)
      (call-with-temporary-directory "ops-consumer-init"
        (lambda (directory)
          (def init (path-expand "init.ss" directory))
          (call-with-output-file init
            (lambda (out)
              (write `(yuanxu! mode: explicit source: ,(path-expand "modules" core-root)
                        (funflow)) out)))
          (def view (yuanxu-load-modules init))
          (check-equal? (.get view selected-graph module-order) '(funflow))
          ((.get view admit-current))
          (call-with-output-file (list path: init append: #t)
            (cut display "\n;; changed consumer declaration\n" <>))
          (check-exception ((.get view admit-current)) error?)
          ;; Scope configuration is an inert library value, not a selected role.
          (check-equal? (.get Ops prototypes Script command) '()))))))
