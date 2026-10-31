;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: re-exports the public POO-native feature-system surface.
;;; Invariant: implementation ownership remains in the imported feature modules.
(import :yuanxu/feature-system/model
        :yuanxu/feature-system/resolver
        :yuanxu/feature-system/feature-manifest
        :yuanxu/feature-system/composition
        :yuanxu/feature-system/capability-model
        :yuanxu/feature-system/domain-case-assembly
        :yuanxu/feature-system/policy-strategy-binding
        :yuanxu/feature-system/adapter-projection-binding
        :yuanxu/feature-system/runtime-handoff-plan
        :yuanxu/feature-system/bundle-v1-domain-case-projection
        :yuanxu/feature-system/bundle-v1-foreign-arena
        :yuanxu/feature-system/bundle-v1-writer
        "source-lock-feature.ss"
        :yuanxu/feature-system/syntax)

(export (import: :yuanxu/feature-system/model)
        (import: :yuanxu/feature-system/resolver)
        (import: :yuanxu/feature-system/feature-manifest)
        (import: :yuanxu/feature-system/composition)
        (import: :yuanxu/feature-system/capability-model)
        (import: :yuanxu/feature-system/domain-case-assembly)
        (import: :yuanxu/feature-system/policy-strategy-binding)
        (import: :yuanxu/feature-system/adapter-projection-binding)
        (import: :yuanxu/feature-system/runtime-handoff-plan)
        (import: :yuanxu/feature-system/bundle-v1-domain-case-projection)
        (import: :yuanxu/feature-system/bundle-v1-foreign-arena)
        (import: :yuanxu/feature-system/bundle-v1-writer)
        (import: "source-lock-feature.ss")
        (import: :yuanxu/feature-system/syntax))
