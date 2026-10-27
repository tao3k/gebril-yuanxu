;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Integration boundary: actual native role expansion and initializer laziness.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in "./qualification/module-scale/fixture.ss" DeclarationFixture)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer))
(export module-deferred-reader-test)
(def (replace-forms path forms)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms))))
(def (module-path fixture name)
  (path-expand name (path-expand "modules/module-0" (.get fixture root))))
(def module-deferred-reader-test
  (test-suite "Guarded declaration selection and native delayed role values"
    (yuanxu-test-fixture "real init preflights Types while business roles remain cold"
      (fixture (.cc DeclarationFixture size: 2))
      (replace-forms (module-path fixture "config.ss")
        '((def Config (error "config demanded")) (export Config)))
      (replace-forms (module-path fixture "objects.ss")
        '((def Scope (error "objects demanded")) (export Scope)))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            core: (.o requires: (.o) scope-contract: ScopeContract
                      exports: (.o config: Config object: Scope))
            features: (.o unused: (error "unselected Feature forced")))))
      (def expansions 0)
      (def (observe key amount)
        (when (eq? (if (pair? key) (car key) key) 'reader-body-expanded)
          (set! expansions (+ expansions amount))))
      (parameterize ((current-module-source-observer observe))
        (def graph (.get fixture modules module-0 tests source selected-graph))
        (check-equal? (length (.get graph module-order)) 2)
        (check-equal? expansions 4)
        (check-equal? (.ref/cached (.get fixture modules module-0) 'scope) #f)
        (def scope (.get fixture modules module-0 scope))
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
            core: (.o requires: (.o) scope-contract: ScopeContract
                      exports: (.o object: Scope))
            features: (.o unused: (error "unselected Feature forced")))))
      (check-equal? (.get fixture modules module-0 scope object) 'source-owned))
    (yuanxu-test-fixture "invalid publication Contract is refused during selection"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "types.ss")
        '((def ScopeContract #f) (export ScopeContract)))
      (check-exception (.get fixture modules module-0 tests source selected-graph) error?))
    (yuanxu-test-fixture "implicit Config stays lazy and uses its native binding"
      (fixture (.cc DeclarationFixture size: 1))
      (replace-forms (module-path fixture "config.ss")
        '((def Config (.o value: 7))))
      (replace-forms (module-path fixture "objects.ss")
        '((def Scope (error "unused Objects role was forced")) (export Scope)))
      (replace-forms (module-path fixture "interface.ss")
        '((.def Module identity: 'module-0
            core: (.o requires: (.o) scope-contract: ScopeContract exports: Config)
            features: (.o))))
      (check-equal? (length (.get fixture modules module-0 tests source selected-graph module-order)) 1)
      (check-equal? (.ref/cached (.get fixture modules module-0) 'scope) #f)
      (check-equal? (.get fixture modules module-0 scope value) 7))
    ))
