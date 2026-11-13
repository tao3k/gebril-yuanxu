;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real role sources and init; assertions run in the owning std/test Case.
(import "../module-init/fixture.ss" "./workloads.ss" (except-in :clan/poo/object .def .o) :tao3k/yuanxu/object-syntax/path-slots :std/test
        (only-in :std/source this-source-file)
        (only-in :tao3k/yuanxu/ops/progress execution-progress!)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :tao3k/yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :tao3k/yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :tao3k/yuanxu/observability/testing-case
                 yuanxu-test-checkpoint yuanxu-selected-testing-case-profile))
(export DeclarationFixture RuntimeValueFixture RuntimeSelectionFixture RuntimeAttributionFixture ModuleEvalOnceFixture BusinessEvalOnceFixture
        SparseBusinessEvalFixture SparseBusinessAttributionFixture
        declaration-scale-case declaration-scale-profile)
(def (declaration-scale-profile count (performance-gate? #t))
  ;; Capacity Cases have time to finish under the hosted runner's GC load.
  ;; The outer process budget also covers importing and reporting.
  (def selected (yuanxu-selected-testing-case-profile))
  (let (profile (.cc selected max-duration-milliseconds:
                  (if performance-gate? 180000 650000)))
    (if (= count 10000)
      (.cc profile heap-limit-bytes: 4294967296 live-growth-limit-bytes: 4294967296)
      profile)))
(def (declaration-stage name action)
  ;; A handful of real phase boundaries survive a failed outer watchdog.
  ;; No per-module sampling, second runner or retained graph is introduced.
  (displayln "declaration-stage start=" name)
  (force-output)
  (let (started (real-time))
    (begin0 (action)
      (displayln "declaration-stage end=" name " seconds=" (- (real-time) started))
      (force-output))))
(def (write-forms path forms)
  (create-directory* (path-directory path))
  (call-with-output-file path
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms))))
(.def DeclarationFixture
  size: 16
  runtime-values?: #f
  poison-unselected?: #f
  profile-selection?: #f
  open-role-payloads?: #f
  .verify: verify-declaration-scale
  .acquire:
  (lambda ()
    (def fixture-root (path-normalize (make-temporary-file-name "declaration-scale-")))
    (def writes 0)
    (def started (real-time))
    (def (write-fixture-source path forms)
      (write-forms path forms)
      (set! writes (1+ writes))
      (execution-progress! (list 'fixture-source-written fixture-root) writes))
    (def (payload expression)
      (if open-role-payloads? `(let () ,expression) expression))
    (displayln "declaration-stage start=fixture-materialization")
    (force-output)
    (create-directory fixture-root)
    (with-catch
      (lambda (failure) (clear-temporary-file! fixture-root) (raise failure))
      (lambda ()
        (def ids
          (map (lambda (index) (string->symbol (string-append "module-" (number->string index))))
            (iota size)))
        (write-fixture-source (path-expand "gerbil.pkg" fixture-root)
          (list (list 'package: (string->symbol (symbol->string (gensym 'declaration-scale-))))))
        (write-fixture-source (path-expand "init.ss" fixture-root)
          (if profile-selection?
                 '((import :tao3k/yuanxu/module-system/selection/init-syntax)
                   (yuanxu! :test-dir "./t" source: "./modules" mode: auto profile: security))
                 `((import :tao3k/yuanxu/module-system/selection/init-syntax)
                   (yuanxu! :test-dir "./t" source: "./modules" mode: explicit ,@(map list ids)))))
        (for-each
          (lambda (id)
            (def directory (path-expand (symbol->string id) (path-expand "modules" fixture-root)))
            (write-fixture-source (path-expand "types.ss" directory)
              '((import (only-in :clan/poo/mop Type.)
                        (only-in :clan/poo/object object?))
                (def ScopeContract
                  (.cc Type. identity: 'scale/scope .element?: object?))
                (export ScopeContract)))
            (write-fixture-source (path-expand "objects.ss" directory)
              (if runtime-values?
                `((import (only-in :clan/poo/object .def .get with-slot-dependencies))
                  (def evaluations ,(if (and poison-unselected?
                                            (not (memq id '(module-0 module-1))))
                                      '(error "unselected Objects initializer ran") 0))
                  (.def (Scope. scope [] config)
                    plan: (with-slot-dependencies scope
                            (lambda ()
                              (set! evaluations (1+ evaluations))
                              (list (.get config port))))
                    computations: (lambda () evaluations)
                    unselected: (error "unselected runtime value forced"))
                  (export Scope.))
                '((import (only-in :clan/poo/object .o))
                  (def Scope (.o ready: #t)) (export Scope))))
            (write-fixture-source (path-expand "config.ss" directory)
              (if runtime-values?
                `((def Config ,(if (and poison-unselected?
                                       (not (memq id '(module-0 module-1))))
                                 '(error "unselected Config initializer ran")
                                 '(.o port: 5432))))
                '((def Config 'configured) (export Config))))
            (write-fixture-source (path-expand "interface.ss" directory)
              `(,@(if (eq? id 'module-0) '()
                    '((import (rename-in (only-in "../module-0/types.ss" ScopeContract)
                                         (ScopeContract ProviderScopeContract)))))
                (.def Module identity: ',id
                  ,@(if profile-selection?
                        (list 'tags: (list 'quote (if (eq? id 'module-1) '(security audited) '(other))))
                        '())
                  core: (.o scope-contract: ScopeContract
                            exports: ,(payload
                                        (if runtime-values?
                                          '(.o (:: @ Scope.) config: Config)
                                          '(error "declaration discovery forced a business scope"))))
                  features: (.o unused: ,(payload '(error "unselected Feature forced"))))))) ids)
        (displayln "declaration-stage end=fixture-materialization seconds=" (- (real-time) started))
        (force-output)
        (yuanxu-write-observation-line! "declaration-scale-artifact modules=%s root=%s" size fixture-root)
        (when (and runtime-values? poison-unselected?)
          (yuanxu-write-observation-line!
            "business-eval-guard owners=%s unrelated=%s roles=objects,config action=refuse-initialization"
            size (max 0 (- size 2))))
        (.o (:: resource [] exports)
            root: fixture-root
            exports:
            (parameterize ((current-expander-context (make-top-context)))
              (declaration-stage 'init-import
                (lambda () (import-fixture-init! (path-expand "init.ss" fixture-root)))))
            modules: (declaration-stage 'module-namespace (lambda () (.get exports modules)))))))
  .release:
  (lambda (fixture)
    (clear-temporary-file! (.get fixture root))
    (check-equal? (file-exists? (.get fixture root)) #f)))

(.def (RuntimeValueFixture @ DeclarationFixture)
  runtime-values?: #t
  .verify: verify-runtime-scale)
(.def (RuntimeSelectionFixture @ RuntimeValueFixture)
  .verify: verify-runtime-selection)
(.def (RuntimeAttributionFixture @ RuntimeValueFixture)
  .verify: (cond-expand
             (yuanxu-module-test-stage-accounting
              (lambda (exports count source-root)
                (verify-runtime-attribution exports count source-root accounting?: 'stages)))
             (else verify-runtime-attribution)))
(.def (ModuleEvalOnceFixture @ RuntimeValueFixture)
  .verify: verify-module-eval-once)
(.def (BusinessEvalOnceFixture @ RuntimeValueFixture)
  ;; Metadata admission must not run unrelated Objects or Config bodies.
  ;; Keep the declaration count and the existing initializer/definition count.
  poison-unselected?: #t
  .verify: verify-business-eval-once)
(.def (SparseBusinessEvalFixture @ BusinessEvalOnceFixture)
  profile-selection?: #t
  .verify: verify-sparse-business-eval)
(.def (SparseBusinessAttributionFixture @ SparseBusinessEvalFixture)
  .verify: verify-sparse-business-attribution)

;; Internal test declaration: no runner, execution policy or module list is copied.
(defrules declaration-scale-case ()
  ((_ description count)
   (declaration-scale-case description count DeclarationFixture))
  ((_ description count fixture-profile)
   (declaration-scale-case description count fixture-profile #t))
  ((_ description count fixture-profile performance-gate?)
   (yuanxu-test-fixture description profile: (declaration-scale-profile count performance-gate?)
     (fixture (.cc fixture-profile size: count))
     (yuanxu-test-checkpoint 'fixture-ready)
     ;; This is the assertion workload of this SAME official std/test Case.
     ;; No nested .run, compiler/signing pass or second Harness is started.
     (.call fixture-profile .verify (.get fixture exports) count (.get fixture root)))))
