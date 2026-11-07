;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: re-exports the public POO feature-system surface.
;;; Invariant: implementation ownership remains in the imported feature modules.
(import :yuanxu/module-system/feature/model
        :yuanxu/module-system/feature/resolver
        :yuanxu/module-system/feature/feature-manifest
        :yuanxu/module-system/feature/composition
        :yuanxu/module-system/feature/capability-model
        :yuanxu/module-system/feature/domain-case-assembly
        :yuanxu/module-system/feature/policy-strategy-binding
        :yuanxu/module-system/feature/adapter-projection-binding
        :yuanxu/module-system/feature/runtime-handoff-plan
        :yuanxu/module-system/feature/bundle-v1-domain-case-projection
        :yuanxu/module-system/feature/bundle-v1-foreign-arena
        :yuanxu/module-system/feature/bundle-v1-writer
        "source-lock-feature.ss"
        :yuanxu/module-system/feature/syntax)

(export (import: :yuanxu/module-system/feature/model)
        (import: :yuanxu/module-system/feature/resolver)
        (import: :yuanxu/module-system/feature/feature-manifest)
        (import: :yuanxu/module-system/feature/composition)
        (import: :yuanxu/module-system/feature/capability-model)
        (import: :yuanxu/module-system/feature/domain-case-assembly)
        (import: :yuanxu/module-system/feature/policy-strategy-binding)
        (import: :yuanxu/module-system/feature/adapter-projection-binding)
        (import: :yuanxu/module-system/feature/runtime-handoff-plan)
        (import: :yuanxu/module-system/feature/bundle-v1-domain-case-projection)
        (import: :yuanxu/module-system/feature/bundle-v1-foreign-arena)
        (import: :yuanxu/module-system/feature/bundle-v1-writer)
        (import: "source-lock-feature.ss")
        (import: :yuanxu/module-system/feature/syntax))
