;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: re-exports the public POO feature-system surface.
;;; Invariant: implementation ownership remains in the imported feature modules.
(import :yuanxu/module-system/feature-system/model
        :yuanxu/module-system/feature-system/resolver
        :yuanxu/module-system/feature-system/feature-manifest
        :yuanxu/module-system/feature-system/composition
        :yuanxu/module-system/feature-system/capability-model
        :yuanxu/module-system/feature-system/domain-case-assembly
        :yuanxu/module-system/feature-system/policy-strategy-binding
        :yuanxu/module-system/feature-system/adapter-projection-binding
        :yuanxu/module-system/feature-system/runtime-handoff-plan
        :yuanxu/module-system/feature-system/bundle-v1-domain-case-projection
        :yuanxu/module-system/feature-system/bundle-v1-foreign-arena
        :yuanxu/module-system/feature-system/bundle-v1-writer
        "source-lock-feature.ss"
        :yuanxu/module-system/feature-system/syntax)

(export (import: :yuanxu/module-system/feature-system/model)
        (import: :yuanxu/module-system/feature-system/resolver)
        (import: :yuanxu/module-system/feature-system/feature-manifest)
        (import: :yuanxu/module-system/feature-system/composition)
        (import: :yuanxu/module-system/feature-system/capability-model)
        (import: :yuanxu/module-system/feature-system/domain-case-assembly)
        (import: :yuanxu/module-system/feature-system/policy-strategy-binding)
        (import: :yuanxu/module-system/feature-system/adapter-projection-binding)
        (import: :yuanxu/module-system/feature-system/runtime-handoff-plan)
        (import: :yuanxu/module-system/feature-system/bundle-v1-domain-case-projection)
        (import: :yuanxu/module-system/feature-system/bundle-v1-foreign-arena)
        (import: :yuanxu/module-system/feature-system/bundle-v1-writer)
        (import: "source-lock-feature.ss")
        (import: :yuanxu/module-system/feature-system/syntax))
