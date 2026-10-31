;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Reusable native admission adapter; diagnostics retain JSON Schema paths.
(import :clan/poo/object
        (only-in :yuanxu/object-types/contracts YuanxuContract.)
        "./json-schema-receipt.ss"
        (only-in "./contracts.ss" SchemaContract.)
        (only-in "./json-schema-ir.ss" yuanxu-json-schema-normalization-schema))
(export yuanxu-json-schema->contract)

(def (yuanxu-json-schema->contract identity-value schema-value)
  (let (artifact (yuanxu-json-schema->contract-artifact schema-value))
    ;; Unsupported/invalid source constraints may not silently weaken admission.
    (unless (and (yuanxu-json-schema-contract-artifact-valid? artifact)
                 (null? (yuanxu-json-schema-contract-artifact-diagnostics artifact)))
      (error "JSON Schema admission requires supported constraints" artifact))
    (let* ((node (yuanxu-json-schema-normalization-schema
                   (yuanxu-json-schema-contract-artifact-normalization artifact)))
           (schema-type (.cc SchemaContract. 'identity identity-value 'node node)))
      (.o (:: @ [YuanxuContract.] value-type)
           identity: identity-value
           ;; SchemaContract owns native value validation and POO diagnostics.
           ;; The standard admission boundary converts its TypeError to refusal;
           ;; do not classify again using the backend's private diagnostic records.
           value-contract: value-type schema: schema-value sexp: identity-value
           schema-artifact: artifact
           value-type: schema-type))))
