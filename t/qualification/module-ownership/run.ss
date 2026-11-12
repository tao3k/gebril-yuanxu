;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Runtime source controls using the installed std/test harness.
(import :std/test/base
        (only-in "../../composition-roles-test.ss" composition-roles-test)
        (only-in "../../domain-case-indexed-resolution-test.ss" domain-case-indexed-resolution-test)
        (only-in "../../domain-case-syntax-test.ss" domain-case-syntax-test)
        (only-in "../../domain-case-test.ss" domain-case-test)
        (only-in "../../feature-adapter-projection-binding-test.ss" feature-adapter-projection-binding-test)
        (only-in "../../feature-bundle-v1-domain-case-projection-test.ss" feature-bundle-v1-domain-case-projection-test)
        (only-in "../../feature-bundle-v1-foreign-arena-test.ss" feature-bundle-v1-foreign-arena-test)
        (only-in "../../feature-bundle-v1-lowering-test.ss" feature-bundle-v1-lowering-test)
        (only-in "../../feature-composition-test.ss" feature-composition-test)
        (only-in "../../feature-domain-case-assembly-test.ss" feature-domain-case-assembly-test)
        (only-in "../../feature-manifest-test.ss" feature-manifest-test)
        (only-in "../../feature-policy-strategy-binding-test.ss" feature-policy-strategy-binding-test)
        (only-in "../../feature-runtime-handoff-plan-test.ss" feature-runtime-handoff-plan-test)
        (only-in "../../feature-sources-lock-test.ss" feature-sources-lock-test)
        (only-in "../../feature-syntax-test.ss" feature-syntax-test)
        (only-in "../../feature-test.ss" feature-test)
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
        feature-adapter-projection-binding-test
        feature-bundle-v1-domain-case-projection-test
        feature-bundle-v1-foreign-arena-test
        feature-bundle-v1-lowering-test
        feature-composition-test
        feature-domain-case-assembly-test
        feature-manifest-test
        feature-policy-strategy-binding-test
        feature-runtime-handoff-plan-test
        feature-sources-lock-test
        feature-syntax-test
        feature-test
        utilities-functional-test
        poo-clos-syntax-test
        poo-clos-method-bundle-test
        path-slots-test
        module-scope-syntax-test)
