;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: emit Yuanxu object contracts from normalized JSON Schema IR.
;;; Optimization boundary: this module builds predicate closures once while
;;; emitting contracts; value validation reuses those closures without walking
;;; the normalized schema again.

(import (only-in :clan/poo/object
                 .alist
                 .ref
                 .slot?
                 object?)
        (only-in :std/text/pregexp
                 pregexp
                 pregexp-match)
        (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-contract-slot
                 yuanxu-contract-value-type
                 yuanxu-object-contract)
        (only-in :yuanxu/utilities/functional
                 yuanxu-all?
                 yuanxu-find
                 yuanxu-predicate-and
                 yuanxu-predicate-or
                 yuanxu-predicate-exactly-one)
        (only-in "./json-schema-constraints.ss"
                 yuanxu-json-schema-apply-node-constraints)
        (only-in "./functional.ss"
                 yuanxu-contract-key->string
                 yuanxu-contract-all?
                 yuanxu-contract-json-object?
                 yuanxu-contract-member?
                 yuanxu-contract-project-list
                 yuanxu-contract-filter-map)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node?
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-node->alist
                 yuanxu-json-schema-property-name
                 yuanxu-json-schema-property-schema
                 yuanxu-json-schema-property-required?
                 yuanxu-json-schema-property-doc
                 yuanxu-json-schema-property-metadata
                 yuanxu-json-schema-property->alist
                 yuanxu-json-schema-object?
                 yuanxu-json-schema-object-properties
                 yuanxu-json-schema-object-additional-properties
                 yuanxu-json-schema-object-pattern-properties
                 yuanxu-json-schema-object-metadata
                 yuanxu-json-schema-pattern-property?
                 yuanxu-json-schema-pattern-property->alist))


(export yuanxu-json-schema-any?
        yuanxu-json-schema-null?
        yuanxu-json-schema-json-object-value?
        yuanxu-json-schema-json-array-value?
        yuanxu-json-schema-integer-value?
        yuanxu-json-schema-symbol-string
        yuanxu-json-schema-contract-key
        yuanxu-json-schema-node-value-kind
        yuanxu-json-schema-node-predicate-key
        yuanxu-json-schema-node-predicate
        yuanxu-json-schema-property->slot-contract
        yuanxu-json-schema-object-node->object-type-contract
        yuanxu-json-schema-node->object-type-contract)

(import :yuanxu/modules/json-schema/json-schema-emit-runtime
        :yuanxu/modules/json-schema/json-schema-emit-contracts)
