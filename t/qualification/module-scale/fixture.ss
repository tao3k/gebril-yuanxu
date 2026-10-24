;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real role sources and init; execution remains the existing init tests .run.
(import "../module-init/fixture.ss" (except-in :clan/poo/object .def .o) :yuanxu/object-syntax/path-slots :std/test
        (only-in :std/source this-source-file)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-test-checkpoint yuanxu-selected-testing-case-profile))
(export DeclarationFixture declaration-scale-case declaration-scale-profile)
(def (declaration-scale-profile count)
  (let (profile (yuanxu-selected-testing-case-profile))
    (if (= count 10000)
      (.cc profile live-growth-limit-bytes: 2147483648)
      profile)))
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
    (def writes 0)
    (def (write-fixture-source path forms)
      (write-forms path forms)
      (set! writes (1+ writes))
      (execution-progress! (list 'fixture-source-written fixture-root) writes))
    (create-directory fixture-root)
    (with-catch
      (lambda (failure) (clear-temporary-file! fixture-root) (raise failure))
      (lambda ()
        (def ids
          (map (lambda (index) (string->symbol (string-append "module-" (number->string index))))
            (iota size)))
        (write-fixture-source (path-expand "gerbil.pkg" fixture-root)
          (list (list 'package: (symbol->string (gensym 'declaration-scale-)))))
        (write-fixture-source (path-expand "init.ss" fixture-root)
          `((import :yuanxu/module-system/selection/init-syntax)
            (yuanxu! source: "./modules" mode: explicit ,@(map list ids))))
        (for-each
          (lambda (id)
            (def directory (path-expand (symbol->string id) (path-expand "modules" fixture-root)))
            (write-fixture-source (path-expand "types.ss" directory)
              '((import (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
                        (only-in :clan/poo/object object?))
                (def ScopeContract
                  (yuanxu-predicate-contract 'scale/scope object? (lambda (_v _c) '())))
                (export ScopeContract)))
            (write-fixture-source (path-expand "objects.ss" directory)
              '((import (only-in :clan/poo/object .o))
                (def Scope (.o ready: #t)) (export Scope)))
            (write-fixture-source (path-expand "config.ss" directory)
              '((def Config 'configured) (export Config)))
            (write-fixture-source (path-expand "interface.ss" directory)
              `((.def Module identity: ',id
                  core: (.o requires: ,(if (eq? id 'module-0) '(.o)
                                           '(.o Shared: (.o module-id: 'module-0 contract: ScopeContract)))
                            scope-contract: ScopeContract
                            exports: (error "declaration discovery forced a business scope"))
                  features: (.o unused: (error "unselected Feature forced")))))) ids)
        (def test (path-expand "modules/module-0/tests/worker-test.ss" fixture-root))
        (create-directory* (path-directory test))
        (copy-file worker test)
        (yuanxu-write-observation-line! "declaration-scale-artifact modules=%s observation-log=%s" size observation-log)
        (.o root: fixture-root log: observation-log
            modules:
            (parameterize ((current-expander-context (make-top-context)))
              (.get (import-fixture-init! (path-expand "init.ss" fixture-root)) modules))))))
  .release:
  (lambda (fixture)
    (clear-temporary-file! (.get fixture root))
    (check-equal? (file-exists? (.get fixture root)) #f)))

;; Internal test declaration: no runner, worker policy or module list is copied.
(defrules declaration-scale-case ()
  ((_ description count)
   (yuanxu-test-fixture description profile: (declaration-scale-profile count)
     (fixture (.cc DeclarationFixture size: count))
     (yuanxu-test-checkpoint 'fixture-ready)
     (def module (.get fixture modules module-0))
     (check-equal? (.ref/cached module 'scope) #f)
     (def tests (.get module tests))
     (.def (Observed @ tests)
       execution.profile.emit?: #t
       ;; Capacity is checked with the normal policy, not the optional full
       ;; read-token/SDK-context census. Worker assertions and source-event
       ;; counters stay active; its explicit capacity policy owns the budget.
       execution.log: (.get fixture log))
     (check-equal? (eq? (.get Observed source) (.get tests source)) #t)
     ;; This worker has no package-local support to compile. Its own Case
     ;; explicitly demands the complete Graph; parent preparation must not.
     (check-equal? (.ref/cached (.get tests source) 'selected-graph) #f)
     (.call Observed .run)
     (check-equal? (.ref/cached (.get tests source) 'selected-graph) #f)
     (check-equal? (.ref/cached module 'scope) #f))))
