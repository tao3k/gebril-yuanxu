;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Runtime source controls using the installed std/test harness.
(import :std/test/base
        (only-in "../../composition-roles-test.ss" composition-roles-test)
        (only-in "../../domain-case-indexed-resolution-test.ss" domain-case-indexed-resolution-test)
        (only-in "../../domain-case-syntax-test.ss" domain-case-syntax-test)
        (only-in "../../domain-case-test.ss" domain-case-test)
        (only-in "../../feature-system-adapter-projection-binding-test.ss" feature-system-adapter-projection-binding-test)
        (only-in "../../feature-system-bundle-v1-domain-case-projection-test.ss" feature-system-bundle-v1-domain-case-projection-test)
        (only-in "../../feature-system-bundle-v1-foreign-arena-test.ss" feature-system-bundle-v1-foreign-arena-test)
        (only-in "../../feature-system-bundle-v1-lowering-test.ss" feature-system-bundle-v1-lowering-test)
        (only-in "../../feature-system-composition-test.ss" feature-system-composition-test)
        (only-in "../../feature-system-domain-case-assembly-test.ss" feature-system-domain-case-assembly-test)
        (only-in "../../feature-system-manifest-test.ss" feature-system-manifest-test)
        (only-in "../../feature-system-policy-strategy-binding-test.ss" feature-system-policy-strategy-binding-test)
        (only-in "../../feature-system-runtime-handoff-plan-test.ss" feature-system-runtime-handoff-plan-test)
        (only-in "../../feature-system-sources-lock-test.ss" feature-system-sources-lock-test)
        (only-in "../../feature-system-syntax-test.ss" feature-system-syntax-test)
        (only-in "../../feature-system-test.ss" feature-system-test)
        (only-in "../../utilities-functional-test.ss" utilities-functional-test)
        (only-in "../../poo-clos-syntax-test.ss" poo-clos-syntax-test)
        (only-in "../../poo-clos-method-bundle-test.ss" poo-clos-method-bundle-test)
        (only-in "../../path-slots-test.ss" path-slots-test)
        (only-in "../../module-scope-syntax-test.ss" module-scope-syntax-test))

;; Export the existing std/test suites. Gerbil owns their lifecycle and verdict.
(export composition-roles-test
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
        module-scope-syntax-test)
