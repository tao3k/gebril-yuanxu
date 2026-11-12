;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: public POO interface of the Module System Feature component.
;;; Invariant: implementation ownership remains in the imported feature modules.
(import :tao3k/yuanxu/module-system/feature/model
        :tao3k/yuanxu/module-system/feature/resolver
        :tao3k/yuanxu/module-system/feature/feature-manifest
        :tao3k/yuanxu/module-system/feature/composition
        :tao3k/yuanxu/module-system/feature/capability-model
        :tao3k/yuanxu/module-system/feature/domain-case-assembly
        :tao3k/yuanxu/module-system/feature/policy-strategy-binding
        :tao3k/yuanxu/module-system/feature/adapter-projection-binding
        :tao3k/yuanxu/module-system/feature/runtime-handoff-plan
        :tao3k/yuanxu/module-system/feature/bundle-v1-domain-case-projection
        :tao3k/yuanxu/module-system/feature/bundle-v1-foreign-arena
        :tao3k/yuanxu/module-system/feature/bundle-v1-writer
        "source-lock-feature.ss"
        :tao3k/yuanxu/module-system/feature/syntax)

(export (import: :tao3k/yuanxu/module-system/feature/model)
        (import: :tao3k/yuanxu/module-system/feature/resolver)
        (import: :tao3k/yuanxu/module-system/feature/feature-manifest)
        (import: :tao3k/yuanxu/module-system/feature/composition)
        (import: :tao3k/yuanxu/module-system/feature/capability-model)
        (import: :tao3k/yuanxu/module-system/feature/domain-case-assembly)
        (import: :tao3k/yuanxu/module-system/feature/policy-strategy-binding)
        (import: :tao3k/yuanxu/module-system/feature/adapter-projection-binding)
        (import: :tao3k/yuanxu/module-system/feature/runtime-handoff-plan)
        (import: :tao3k/yuanxu/module-system/feature/bundle-v1-domain-case-projection)
        (import: :tao3k/yuanxu/module-system/feature/bundle-v1-foreign-arena)
        (import: :tao3k/yuanxu/module-system/feature/bundle-v1-writer)
        (import: "source-lock-feature.ss")
        (import: :tao3k/yuanxu/module-system/feature/syntax))
