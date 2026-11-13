;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Integration boundary: actual runtime role expansion and initializer laziness.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander eval-module module-context? module-context-path module-context-export)
        (only-in :gerbil/expander/module __module-registry)
        (only-in :std/error Error? Error-message)
        (only-in :tao3k/yuanxu/t/qualification/module-scale/fixture DeclarationFixture RuntimeValueFixture)
        (only-in :tao3k/yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source)
        (only-in :tao3k/yuanxu/module-system/authoring/admission YuanxuModuleAuthoringAdmission)
        (only-in :tao3k/yuanxu/module-system/source/reader module-publication-reader)
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration current-module-role-resolver)
        (only-in :tao3k/yuanxu/module-system/source/admission current-module-source-observer))
(export module-deferred-reader-test)
(def (replace-forms path forms)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms))))
(def (module-path fixture name)
  (path-expand name (path-expand "modules/module-0" (.get fixture root))))
(def module-deferred-reader-test
  (test-suite "Guarded declaration selection and runtime delayed role values"
    (test-case "a closed private wrapper delivers its value without retaining an export"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def previous (make-hash-table-eq))
          (hash-for-each (lambda (_ context) (hash-put! previous context #t)) __module-registry)
          (def (private-interfaces)
            (def owners (make-hash-table-eq))
            (hash-for-each
              (lambda (_ context)
                (when (and (not (hash-key? previous context)) (module-context? context)
                           (let (path (module-context-path context))
                             (and (string? path) (string-contains path "/publication-reader-")
                                  (string-suffix? "-interface.ss" path))))
                  (hash-put! owners context #t)))
              __module-registry)
            (hash-keys owners))
          (def delivered '())
          (def publication
            (parameterize ((current-module-source-observer
                            (lambda (key _amount)
                              (when (and (pair? key) (eq? (car key) 'publication-end))
                                (set! delivered (private-interfaces))))))
              (.call (module-publication-reader) read source)))
          (check-equal? (length delivered) 1)
          (check-equal? (private-interfaces) '())
          (def build-context (car delivered))
          (check-equal? (module-context-export build-context) '())
          (check-equal? (void? (eval-module build-context)) #t)
          (check-equal? (.get publication identity) 'custom/example)
          (def scope
            (parameterize ((current-module-role-resolver
                            (lambda _ (error "ambient resolver must remain unused"))))
              (check-equal? (object? (.get publication core scope-contract)) #t)
              (.get publication core exports)))
          (check-equal? (.get scope greeting) "hello")
          (check-equal? (.get scope retained) 'upstream))))
    (test-case "private role imports are observed before their values are demanded"
      (with-publication-source
        (lambda (_root module-root source _view)
          (def helper (path-expand "private.ss" module-root))
          (replace-forms helper
            '((def Private (error "private initializer ran")) (export Private)))
          (def reader (module-publication-reader))
          (def publication (.call reader read source))
          (check-equal? (object? (.get publication core scope-contract)) #t)
          (replace-forms helper
            '((def Private (error "changed private initializer ran")) (export Private)))
          (def failure (with-catch values (lambda () (.call reader admit-current))))
          (check-equal? (Error? failure) #t)
          (check-equal? (and (string-contains (Error-message failure) "stale") #t) #t))
        roles:
        (.o objects: '((import "private.ss")
                       (def FixtureScope Private)
                       (export FixtureScope)))))
    (test-case "unchanged private role imports use the same guarded runtime value"
      (with-publication-source
        (lambda (_root module-root source _view)
          (replace-forms (path-expand "private.ss" module-root)
            '((import :clan/poo/object)
              (def Private (.o retained: 'private)) (export Private)))
          (def publication (.call (module-publication-reader) read source))
          (def scope (.get publication core exports))
          (check-equal? (.get scope retained) 'private)
          (check-equal? (eq? scope (.get publication core exports)) #t))
        roles:
        (.o objects: '((import "private.ss")
                       (def FixtureScope Private)
                       (export FixtureScope))
            interface:
            '((.def Fixture identity: 'custom/example
                core: (.o scope-contract: FixtureContract
                          exports: FixtureScope)
                features: (.o))))))
    (test-case "delayed roles still refuse a symbolic private source"
      (with-publication-source
        (lambda (_root module-root source _view)
          (create-symbolic-link "/dev/null" (path-expand "private.ss" module-root))
          (check-exception (.call (module-publication-reader) read source) error?))
        roles:
        (.o objects: '((import "private.ss")
                       (def FixtureScope Private)
                       (export FixtureScope)))))
    (test-case "generated role aliases use the current extended POO receiver"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def publication (.call (module-publication-reader) read source))
          (def core (.get publication core))
          (def private-keys
            (filter (lambda (name) (not (memq name '(requires scope-contract link))))
              (.all-slots core)))
          (check-equal? (length private-keys) 1)
          (def roles (.ref core (car private-keys)))
          (def replacement (.o identity: 'replacement))
          (def extended (.cc roles types: (.o FixtureContract: replacement)))
          (check-equal? (eq? (.get extended FixtureContract) replacement) #t)
          (check-equal? (eq? (.get roles FixtureContract) replacement) #f))))
    (test-case "an object slot can shadow the role alias of the same name"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def publication (.call (module-publication-reader) read source))
          (def scope (.get publication core exports))
          (check-equal? (.get scope selected) 'local))
        roles:
        (.o config: '((def Greeting (error "shadowed role was evaluated")) (export Greeting))
            interface:
            '((.def Fixture identity: 'custom/example
                core: (.o scope-contract: FixtureContract
                          exports: (.o Greeting: 'local selected: Greeting))
                features: (.o))))))
    (yuanxu-test-fixture "a selected provider Objects initializer is actually demanded"
      (fixture (.cc RuntimeValueFixture size: 2))
      (replace-forms (module-path fixture "objects.ss")
        '((def evaluations (error "selected provider Objects initializer ran"))
          (.def Scope.) (export Scope.)))
      ;; Admission reads both declarations and Types, but leaves Objects cold.
      (check-equal? (length (.get fixture exports tests selected-graph module-order)) 2)
      (check-exception (.get fixture modules module-1 plan)
        (lambda (cause)
          (and (Error? cause)
               (string=? (Error-message cause) "selected provider Objects initializer ran")))))
    (yuanxu-test-fixture "real init preflights Types while business roles remain cold"
      (fixture (.cc DeclarationFixture size: 2))
      (replace-forms (module-path fixture "config.ss")
        '((def Config (error "config demanded")) (export Config)))
      (replace-forms (module-path fixture "objects.ss")
        '((def Scope (error "objects demanded")) (export Scope)))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            core: (.o scope-contract: ScopeContract
                      exports: (.o config: Config object: Scope))
            features: (.o unused: (error "unselected Feature forced")))))
      (def expansions 0)
      (def (observe key amount)
        (when (eq? (if (pair? key) (car key) key) 'reader-body-expanded)
          (set! expansions (+ expansions amount))))
      (parameterize ((current-module-source-observer observe))
        (def graph (.get (.call (.get fixture exports tests) .select '(module-0)) source selected-graph))
        (check-equal? (length (.get graph module-order)) 2)
        (check-equal? expansions 4)
        (check-equal? (.ref/cached (.get fixture modules) 'module-0) #f)
        (def scope (.get fixture modules module-0))
        (check-equal? expansions 4)
        (def config-error (with-catch values (lambda () (.get scope config))))
        (check-equal? (Error? config-error) #t)
        (check-equal? (Error-message config-error) "config demanded")
        (check-equal? expansions 5)
        (def object-error (with-catch values (lambda () (.get scope object))))
        (check-equal? (Error? object-error) #t)
        (check-equal? (Error-message object-error) "objects demanded")
        (check-equal? expansions 6)))
    (yuanxu-test-fixture "private constructor does not capture a source-owned binding"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "objects.ss")
        '((def object? 'source-owned) (def Scope object?) (export Scope)))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            core: (.o scope-contract: ScopeContract
                      exports: (.o object: Scope))
            features: (.o unused: (error "unselected Feature forced")))))
      (check-equal? (.get fixture modules module-0 object) 'source-owned))
    (yuanxu-test-fixture "invalid publication Contract is refused during selection"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "types.ss")
        '((def ScopeContract #f) (export ScopeContract)))
      (check-exception (.get (.call (.get fixture exports tests) .select '(module-0)) source selected-graph) error?))
    (yuanxu-test-fixture "implicit Config stays lazy and uses its runtime binding"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "config.ss")
        '((def Config (.o value: 7))))
      (replace-forms (module-path fixture "objects.ss")
        '((def Scope (error "unused Objects role was forced")) (export Scope)))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            core: (.o scope-contract: ScopeContract exports: Config)
            features: (.o))))
      (check-equal? (length (.get (.call (.get fixture exports tests) .select '(module-0)) source selected-graph module-order)) 1)
      (check-equal? (.ref/cached (.get fixture modules) 'module-0) #f)
      (check-equal? (.get fixture modules module-0 value) 7))
    (yuanxu-test-fixture "root slot shadow keeps its binding ahead of a bare role alias"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "config.ss")
        '((def Config (error "shadowed Config role was forced"))))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            Config: (.o value: 9)
            core: (.o scope-contract: ScopeContract exports: Config)
            features: (.o))))
      (check-equal? (.get fixture modules module-0 value) 9))
    (yuanxu-test-fixture "the selected Graph keeps the actual authoring receipt Type dependency"
      (fixture (.cc RuntimeValueFixture size: 2))
      (def graph (.get fixture exports tests selected-graph))
      (def current! (.get graph admit-current))
      (def original (.ref YuanxuModuleAuthoringAdmission '.validate))
      (def (stale? cause)
        (and (Error? cause) (string-contains (Error-message cause) "stale")))
      (current!)
      (dynamic-wind
        (lambda () (.put! YuanxuModuleAuthoringAdmission '.validate (lambda (receipt) receipt)))
        (lambda () (check-exception (current!) stale?))
        (lambda () (.put! YuanxuModuleAuthoringAdmission '.validate original)))
      (check-exception (current!) stale?))
    ))
