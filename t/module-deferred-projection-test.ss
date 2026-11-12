;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Closed declaration admission and compiled role export correspondence.
(import (only-in :std/test test-suite test-case check-equal? check-exception)
        (for-template :std/func :std/iter :gerbil/core)
        (rename-in (only-in :std/iter/iterators in-list) (in-list original-in-list))
        (only-in :clan/poo/object .get .o .cc .ref)
        (only-in :yuanxu/modules/json-schema/interface JsonSchema)
        (only-in :yuanxu/module-system/feature/model feature-descriptor)
        (only-in :yuanxu/module-system/source/link module-program-namespace module-program-feature)
        (only-in :gerbil/expander current-expander-module-import current-expander-context make-top-context eval-syntax datum->syntax)
        (only-in :gerbil/runtime/syntax SyntaxError? SyntaxError-message)
        (only-in :yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :yuanxu/module-system/source/deferred-declaration module-deferred-role-exports))
(export module-deferred-projection-test)
(def test-context (current-expander-context))
(def module-deferred-projection-test
  (test-suite "In-memory deferred role projection"
    (test-case "compiled namespace consumes the actual JsonSchema publication without expander imports"
      (def namespace
        (parameterize ((current-expander-module-import
                         (lambda _ (error "compiled publication must not import metadata"))))
          (module-program-namespace 'yuanxu/init
            (.o (yuanxu/modules/json-schema/interface
                  (.o declaration: 'json-schema publication: JsonSchema features: (.o))))
            (.o) '((yuanxu/modules/json-schema/interface))
            '(((json-schema) . yuanxu/modules/json-schema/interface)))))
      (parameterize ((current-expander-module-import
                       (lambda _ (error "compiled scope must not import metadata"))))
        (check-equal? (procedure? (.get (.get namespace json-schema) normalize)) #t)))
    (test-case "compiled namespace refuses relabeled declarations and undeclared dependencies"
      (def (consume value declared)
        (.get (module-program-namespace 'yuanxu/init
                (.o (yuanxu/modules/json-schema/interface
                      (.o declaration: declared publication: value features: (.o))))
                (.o) '((yuanxu/modules/json-schema/interface))
                '(((json-schema) . yuanxu/modules/json-schema/interface))) json-schema))
      (check-exception (consume JsonSchema 'forged) error?)
      (check-exception
        (consume (.cc JsonSchema 'core
                   (.cc (.get JsonSchema core) 'requires
                     (.o missing: (.o module-id: 'outside)))) 'json-schema) error?))
    (test-case "compiled Feature projection checks provenance before qualifying its identities"
      (def refine (lambda (scope) scope))
      (def declared
        (.cc (feature-descriptor (.o feature-id: 'example/metrics owner-module-id: 'example
                                     requires: '(provider/base))) 'refine refine))
      (def expected
        '((kind . feature-descriptor) (feature-id . example/metrics)
          (owner-module-id . example) (requires provider/base)
          (optional-requires) (conflicts)))
      (def (project value)
        (module-program-feature value 'example 'metrics expected
          'pkg/example/metrics 'pkg/example '((pkg/provider/base) () ())))
      (def projected (project declared))
      (check-equal? (.get projected requires) '(pkg/provider/base))
      (check-equal? (eq? (.get projected refine) refine) #t)
      (check-exception (project (.cc declared 'owner-module-id 'forged)) error?)
      (check-exception (project (.cc declared 'feature-id 'forged/metrics)) error?)
      (check-exception (project (.cc declared 'requires '(outside))) error?))
    (test-case "compiled roles read canonical runtime exports without importing metadata"
      (def (values) (compiled-role-values 'std/func '(repeat)))
      (parameterize ((current-expander-context (make-top-context))
                     (current-expander-module-import
                       (lambda _ (error "runtime metadata import is forbidden"))))
        (check-equal? ((.get (values) repeat) (lambda () 42) 2) '(42 42))
        (check-equal? ((.get (values) repeat) (lambda () 7) 1) '(7))))
    (test-case "compiled roles preserve a reexported runtime binding"
      (def values (compiled-role-values 'std/iter '(in-list)))
      (check-equal? (eq? (.get values in-list) original-in-list) #t))
    (test-case "compiled role export mistakes fail during expansion"
      (check-exception
        (parameterize ((current-expander-context test-context))
          (eval-syntax (datum->syntax (quote-syntax compiled-role-values)
                         '(compiled-role-values 'std/func '(missing-export)))))
        (lambda (failure)
          (and (SyntaxError? failure)
               (equal? (SyntaxError-message failure)
                       "compiled role requires one runtime export")))))
    (test-case "syntax exports cannot become compiled runtime values"
      (check-exception
        (parameterize ((current-expander-context test-context))
          (eval-syntax (datum->syntax (quote-syntax compiled-role-values)
                         '(compiled-role-values 'gerbil/core '(when)))))
        (lambda (failure)
          (and (SyntaxError? failure)
               (equal? (SyntaxError-message failure)
                       "compiled role export is not a runtime value")))))
    (test-case "only closed runtime role exports use the deferred projection"
      (def interface
        "(.def Module identity: 'example core: (.o requires: (.o) scope-contract: ScopeContract exports: Config) features: (.o))")
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(def ScopeContract #f) (export ScopeContract)")
            (config . "(def Config #f) (export Config)")))
        '((types ScopeContract) (config Config)))
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(def ScopeContract #f) (export ScopeContract)")
            (config . "(def Config #f) (export Config)"))
          interface-forms: (call-with-input-string interface read-all))
        '((types ScopeContract) (config Config)))
      ;; Preserve the original implicit Config capability. Its runtime binding
      ;; is resolved after role expansion, as the integration Case checks.
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(def ScopeContract #f) (export ScopeContract)")
            (config . "(def Config #f)")))
        '((types ScopeContract) (config Config)))
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(import (only-in :clan/poo/mop define-type)) (define-type (ScopeContract @ [])) (export ScopeContract)")
            (config . "(def Config #f)")))
        '((types ScopeContract) (config Config)))
      (def private-roles '())
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(import (only-in \"private.ss\" Private)) (export ScopeContract)")
            (config . "(def Config #f) (export Config)"))
          private-import: (lambda (role) (set! private-roles (cons role private-roles))))
        '((types ScopeContract) (config Config)))
      (check-equal? private-roles '(types)))))
