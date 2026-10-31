;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: public facade for module object contracts and object-aware wrappers.

(import :yuanxu/module-system/schema/support/contracts
        :yuanxu/module-system/schema/support/slot-policy
        :yuanxu/module-system/schema/support/field-resolution
        :yuanxu/module-system/schema/support/object)

(export yuanxu-module-object-kind
        yuanxu-module-field-contract-kind
        yuanxu-module-field-contribution-kind
        yuanxu-module-transformer-contract-kind
        yuanxu-module-field-resolution-result-kind
        yuanxu-module-objects-root-identity
        YuanxuModuleAnyType
        YuanxuModuleListType
        YuanxuModuleMapType
        YuanxuModuleAlistType
        YuanxuModuleSymbolType
        YuanxuModuleStringType
        YuanxuModuleBooleanType
        YuanxuModuleObjectType
        YuanxuModuleNodeType
        yuanxu-module-list-type
        yuanxu-module-value-type?
        yuanxu-module-value-type-kind
        yuanxu-module-value-type-accepts?
        yuanxu-module-field-contract
        yuanxu-module-field-contract?
        yuanxu-module-field-contract-identity
        yuanxu-module-field-contract-value-type
        yuanxu-module-field-contract-merge
        yuanxu-module-field-contract-default
        yuanxu-module-field-contract-metadata
        yuanxu-module-field-contract-accepts?
        yuanxu-module-field-contract-with-merge
        yuanxu-module-field-contribution
        yuanxu-module-field-contribution?
        yuanxu-module-field-contribution-target
        yuanxu-module-field-contribution-field
        yuanxu-module-field-contribution-value
        yuanxu-module-field-contribution-merge
        yuanxu-module-field-contribution->extension
        yuanxu-module-field-contributions->extensions
        yuanxu-module-slot-apply-policy
        yuanxu-module-transformer-contract
        yuanxu-module-transformer-contract?
        yuanxu-module-transformer-contract-identity
        yuanxu-module-transformer-contract-merge
        yuanxu-module-transformer-contract-input-type
        yuanxu-module-transformer-contract-argument-type
        yuanxu-module-transformer-contract-output-type
        yuanxu-module-transformer-contract-idempotent?
        yuanxu-module-transformer-contract-identity-key
        yuanxu-module-transformer-contract-metadata
        yuanxu-module-transformer-list-append-contract
        yuanxu-module-transformer-list-remove-contract
        yuanxu-module-transformer-map-set-contract
        yuanxu-module-transformer-contract-diagnostics
        yuanxu-module-transformer-contract-valid?
        yuanxu-module-transformer-field-contribution
        yuanxu-module-field-contributions-resolve
        yuanxu-module-field-resolution-result?
        yuanxu-module-field-resolution-result-extension-result
        yuanxu-module-field-resolution-result-contributions
        yuanxu-module-field-resolution-result-root
        yuanxu-module-field-resolution-result-changed-passes
        yuanxu-module-field-resolution-result-applied?
        yuanxu-module-object
        yuanxu-module-object?
        yuanxu-module-object-identity
        yuanxu-module-object-inherits
        yuanxu-module-object-fields
        yuanxu-module-object-metadata
        yuanxu-module-object-inheritance-chain-cache
        yuanxu-module-object-validation-cache
        yuanxu-module-object-resolved-fields
        yuanxu-module-object-field
        yuanxu-module-object-default-slots
        yuanxu-module-object-node/default-slots
        yuanxu-module-object-node
        yuanxu-module-object-contributions
        yuanxu-module-objects-node
        yuanxu-module-objects-index
        yuanxu-module-objects-ref/index
        yuanxu-module-objects-ref
        yuanxu-module-objects-resolve-contributions/node
        yuanxu-module-objects-resolve-contributions)
