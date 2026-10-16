;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: re-exports the public POO-native feature-system surface.
;;; Invariant: implementation ownership remains in the imported feature modules.
(import :core/feature-system/model
        :core/feature-system/resolver
        :core/feature-system/feature-manifest
        :core/feature-system/composition
        :core/feature-system/capability-model
        :core/feature-system/domain-case-assembly
        :core/feature-system/policy-strategy-binding
        :core/feature-system/adapter-projection-binding
        :core/feature-system/runtime-handoff-plan
        :core/feature-system/bundle-v1-domain-case-projection
        :core/feature-system/bundle-v1-foreign-arena
        :core/feature-system/bundle-v1-writer
        "source-lock-feature.ss"
        :core/feature-system/syntax)

(export (import: :core/feature-system/model)
        (import: :core/feature-system/resolver)
        (import: :core/feature-system/feature-manifest)
        (import: :core/feature-system/composition)
        (import: :core/feature-system/capability-model)
        (import: :core/feature-system/domain-case-assembly)
        (import: :core/feature-system/policy-strategy-binding)
        (import: :core/feature-system/adapter-projection-binding)
        (import: :core/feature-system/runtime-handoff-plan)
        (import: :core/feature-system/bundle-v1-domain-case-projection)
        (import: :core/feature-system/bundle-v1-foreign-arena)
        (import: :core/feature-system/bundle-v1-writer)
        (import: "source-lock-feature.ss")
        (import: :core/feature-system/syntax))
