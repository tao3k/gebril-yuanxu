;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Stable emission facade. Implementing owners carry their own dependencies;
;;; this module reexports the original bindings without duplicate preparation.

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
