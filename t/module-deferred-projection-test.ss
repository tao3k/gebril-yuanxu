;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source text is parser input data here: no files or native imports.
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :yuanxu/module-system/source/deferred-declaration module-deferred-role-exports))
(export module-deferred-projection-test)
(def module-deferred-projection-test
  (test-suite "In-memory deferred role projection"
    (test-case "only closed runtime role exports use the deferred projection"
      (def interface
        "(.def Module identity: 'example core: (.o requires: (.o) scope-contract: ScopeContract exports: Config) features: (.o))")
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(def ScopeContract #f) (export ScopeContract)")
            (config . "(def Config #f) (export Config)")))
        '((types ScopeContract) (config Config)))
      ;; Preserve the original implicit Config capability. Its native binding
      ;; is resolved after role expansion, as the integration Case checks.
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(def ScopeContract #f) (export ScopeContract)")
            (config . "(def Config #f)")))
        '((types ScopeContract) (config Config)))
      (check-equal?
        (module-deferred-role-exports interface
          '((types . "(import (only-in \"private.ss\" Private)) (export ScopeContract)")
            (config . "(def Config #f) (export Config)"))) #f))))
