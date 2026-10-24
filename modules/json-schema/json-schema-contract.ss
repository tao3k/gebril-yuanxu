;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Reusable native admission adapter; diagnostics retain JSON Schema paths.
(import :clan/poo/object
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence)
        "./json-schema-receipt.ss"
        (only-in "./contracts.ss" SchemaContract.)
        (only-in "./json-schema-ir.ss" yuanxu-json-schema-normalization-schema)
        (only-in "./json-schema-validate.ss" yuanxu-json-schema-node-validate))
(export yuanxu-json-schema->contract)

(def (yuanxu-json-schema->contract identity schema)
  (let (artifact (yuanxu-json-schema->contract-artifact schema))
    ;; Unsupported/invalid source constraints may not silently weaken admission.
    (unless (and (yuanxu-json-schema-contract-artifact-valid? artifact)
                 (null? (yuanxu-json-schema-contract-artifact-diagnostics artifact)))
      (error "JSON Schema admission requires supported constraints" artifact))
    (let* ((node (yuanxu-json-schema-normalization-schema
                   (yuanxu-json-schema-contract-artifact-normalization artifact)))
           (classify
             (lambda (candidate context)
               (let (failures (yuanxu-json-schema-node-validate node candidate '()))
                 (yuanxu-classification-evidence identity candidate
                   (null? failures) failures context)))))
      (.cc YuanxuContract. 'identity identity
           '.classify classify 'schema schema 'sexp identity
           'schema-artifact artifact
           'value-type (.cc SchemaContract. 'identity identity 'node node)))))
