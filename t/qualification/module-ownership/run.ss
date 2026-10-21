;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native source controls using the installed std/test harness.
(import :std/test/base
        (only-in :yuanxu/t/composition-roles-test composition-roles-test)
        (only-in :yuanxu/t/domain-case-indexed-resolution-test domain-case-indexed-resolution-test)
        (only-in :yuanxu/t/domain-case-syntax-test domain-case-syntax-test)
        (only-in :yuanxu/t/domain-case-test domain-case-test)
        (only-in :yuanxu/t/feature-system-adapter-projection-binding-test feature-system-adapter-projection-binding-test)
        (only-in :yuanxu/t/feature-system-bundle-v1-domain-case-projection-test feature-system-bundle-v1-domain-case-projection-test)
        (only-in :yuanxu/t/feature-system-bundle-v1-foreign-arena-test feature-system-bundle-v1-foreign-arena-test)
        (only-in :yuanxu/t/feature-system-bundle-v1-lowering-test feature-system-bundle-v1-lowering-test)
        (only-in :yuanxu/t/feature-system-composition-test feature-system-composition-test)
        (only-in :yuanxu/t/feature-system-domain-case-assembly-test feature-system-domain-case-assembly-test)
        (only-in :yuanxu/t/feature-system-manifest-test feature-system-manifest-test)
        (only-in :yuanxu/t/feature-system-policy-strategy-binding-test feature-system-policy-strategy-binding-test)
        (only-in :yuanxu/t/feature-system-runtime-handoff-plan-test feature-system-runtime-handoff-plan-test)
        (only-in :yuanxu/t/feature-system-sources-lock-test feature-system-sources-lock-test)
        (only-in :yuanxu/t/feature-system-syntax-test feature-system-syntax-test)
        (only-in :yuanxu/t/feature-system-test feature-system-test)
        (only-in :yuanxu/t/utilities-functional-test utilities-functional-test)
        (only-in :yuanxu/t/poo-clos-syntax-test poo-clos-syntax-test)
        (only-in :yuanxu/t/poo-clos-method-bundle-test poo-clos-method-bundle-test)
        (only-in :yuanxu/t/path-slots-test path-slots-test)
        (only-in :yuanxu/t/module-scope-syntax-test module-scope-syntax-test))

(def results
  (map test-suite!
       (list composition-roles-test
             domain-case-indexed-resolution-test
             domain-case-syntax-test
             domain-case-test
             feature-system-adapter-projection-binding-test
             feature-system-bundle-v1-domain-case-projection-test
             feature-system-bundle-v1-foreign-arena-test
             feature-system-bundle-v1-lowering-test
             feature-system-composition-test
             feature-system-domain-case-assembly-test
             feature-system-manifest-test
             feature-system-policy-strategy-binding-test
             feature-system-runtime-handoff-plan-test
             feature-system-sources-lock-test
             feature-system-syntax-test
             feature-system-test
             utilities-functional-test
             poo-clos-syntax-test
             poo-clos-method-bundle-test
             path-slots-test
             module-scope-syntax-test)))
(when (member #f (map test-result-ok? results)) (exit 1))
(displayln "MODULE-OK t/qualification/module-ownership/run.ss")
(displayln "HARNESS-OK module-ownership 21 suites")
(displayln "OK")
