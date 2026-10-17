;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Reusable native admission adapter; diagnostics retain JSON Schema paths.
(import :clan/poo/object
        (only-in :core/types PooFlowContract. poo-flow-classification-evidence)
        "./json-schema-receipt.ss"
        (only-in "./json-schema-ir.ss" poo-flow-json-schema-normalization-schema)
        (only-in "./json-schema-validate.ss" poo-flow-json-schema-node-validate))
(export poo-flow-json-schema->contract)

(def (poo-flow-json-schema->contract identity schema)
  (let (artifact (poo-flow-json-schema->contract-artifact schema))
    ;; Unsupported/invalid source constraints may not silently weaken admission.
    (unless (and (poo-flow-json-schema-contract-artifact-valid? artifact)
                 (null? (poo-flow-json-schema-contract-artifact-diagnostics artifact)))
      (error "JSON Schema admission requires supported constraints" artifact))
    (let* ((node (poo-flow-json-schema-normalization-schema
                   (poo-flow-json-schema-contract-artifact-normalization artifact)))
           (classify
             (lambda (candidate context)
               (let (failures (poo-flow-json-schema-node-validate node candidate '()))
                 (poo-flow-classification-evidence identity candidate
                   (null? failures) failures context)))))
      (.cc PooFlowContract. 'identity identity
           '.classify classify 'schema schema 'sexp identity))))
