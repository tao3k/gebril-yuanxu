;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real role sources and init; execution remains the existing init tests .run.
(import (except-in :clan/poo/object .def .o) :core/object-syntax/path-slots :std/test
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :core/observability/output poo-flow-write-observation-line!)
        (only-in :core/observability/testing-fixture poo-flow-test-fixture)
        (only-in :core/observability/testing-case poo-flow-test-checkpoint))
(export declaration-scale-case)
(def worker (path-expand "worker-test.ss" (path-directory (this-source-file))))
(def (write-forms path forms)
  (create-directory* (path-directory path))
  (call-with-output-file path
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms))))
(.def DeclarationFixture
  size: 16
  .acquire:
  (lambda ()
    (def fixture-root (path-normalize (make-temporary-file-name "declaration-scale-")))
    (def observation-log (make-temporary-file-name "declaration-scale-observation-"))
    (create-directory fixture-root)
    (with-catch
      (lambda (failure) (clear-temporary-file! fixture-root) (raise failure))
      (lambda ()
        (def ids
          (map (lambda (index) (string->symbol (string-append "module-" (number->string index))))
            (iota size)))
        (write-forms (path-expand "gerbil.pkg" fixture-root)
          (list (list 'package: (symbol->string (gensym 'declaration-scale-)))))
        (write-forms (path-expand "init.ss" fixture-root)
          `((import :core/module-system/selection/init-syntax)
            (poo-flow! source: "./modules" mode: explicit ,@(map list ids))))
        (for-each
          (lambda (id)
            (def directory (path-expand (symbol->string id) (path-expand "modules" fixture-root)))
            (write-forms (path-expand "types.ss" directory)
              '((import (only-in :core/types poo-flow-predicate-contract)
                        (only-in :clan/poo/object object?))
                (def ScopeContract
                  (poo-flow-predicate-contract 'scale/scope object? (lambda (_v _c) '())))
                (export ScopeContract)))
            (write-forms (path-expand "objects.ss" directory)
              '((import (only-in :clan/poo/object .o))
                (def Scope (.o ready: #t)) (export Scope)))
            (write-forms (path-expand "config.ss" directory)
              '((def Config 'configured) (export Config)))
            (write-forms (path-expand "interface.ss" directory)
              `((.def Module identity: ',id
                  core: (.o requires: ,(if (eq? id 'module-0) '(.o)
                                           '(.o Shared: (.o module-id: 'module-0 contract: ScopeContract)))
                            scope-contract: ScopeContract
                            exports: (error "declaration discovery forced a business scope"))
                  features: (.o unused: (error "unselected Feature forced")))))) ids)
        (def test (path-expand "modules/module-0/tests/worker-test.ss" fixture-root))
        (create-directory* (path-directory test))
        (copy-file worker test)
        (poo-flow-write-observation-line! "declaration-scale-artifact modules=%s observation-log=%s" size observation-log)
        (.o root: fixture-root log: observation-log
            modules:
            (parameterize ((current-expander-context (make-top-context)))
              (eval-syntax `(import ,(path-expand "init.ss" fixture-root)))
              (eval-syntax 'init.modules))))))
  .release:
  (lambda (fixture)
    (clear-temporary-file! (.get fixture root))
    (check-equal? (file-exists? (.get fixture root)) #f)))

;; Internal test declaration: no runner, worker policy or module list is copied.
(defrules declaration-scale-case ()
  ((_ description count)
   (poo-flow-test-fixture description (fixture (.cc DeclarationFixture size: count))
     (poo-flow-test-checkpoint 'fixture-ready)
     (def module (.get fixture modules module-0))
     (check-equal? (.ref/cached module 'scope) #f)
     (def tests (.get module tests))
     (.def (Observed @ tests)
       execution.profile.emit?: #t
       execution.profile.trace-enabled?: #t
       execution.log: (.get fixture log))
     (check-equal? (eq? (.get Observed source) (.get tests source)) #t)
     (.call Observed .run)
     (check-equal? (.ref/cached module 'scope) #f))))
