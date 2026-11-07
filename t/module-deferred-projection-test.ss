;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source text is parser input data. Check the wrapper's native bindings too.
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :yuanxu/module-system/source/deferred-declaration module-deferred-role-exports)
        (rename-in (only-in :yuanxu/module-system/source/declaration .def define-module-build-binding)
                   (.def direct-declaration) (define-module-build-binding direct-build))
        (rename-in (only-in :yuanxu/module-system/source/deferred-declaration .def define-module-build-binding)
                   (.def projected-declaration) (define-module-build-binding projected-build))
        (for-syntax (only-in :gerbil/expander free-identifier=?)))
(export module-deferred-projection-test)
(defsyntax (same-wrapper-bindings? stx)
  (if (and (free-identifier=? #'direct-declaration #'projected-declaration)
           (free-identifier=? #'direct-build #'projected-build))
    #'#t
    #'#f))
(def module-deferred-projection-test
  (test-suite "In-memory deferred role projection"
    (test-case "deferred wrapper re-exports the original native bindings"
      (check-equal? (same-wrapper-bindings?) #t))
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
