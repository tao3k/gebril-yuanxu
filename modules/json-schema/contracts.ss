;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Value contracts only. Schema compilation does not import Core admission,
;;; emitted module contracts, observability receipts or provider/Loader policy.
(import (only-in :gerbil/core/contract using)
        (only-in :clan/poo/object .o .cc .ref)
        (only-in :clan/poo/mop Type. define-type)
        (only-in :clan/poo/object-contract diagnose as-value-contract)
        (only-in "./functional.ss" poo-flow-contract-object-ref)
        (only-in "./json-schema-normalize.ss" poo-flow-json-schema-normalize)
        (only-in "./json-schema-ir.ss"
                 poo-flow-json-schema-normalization-schema
                 poo-flow-json-schema-normalization-diagnostics)
        (only-in "./json-schema-valid.ss" poo-flow-json-schema-node-valid?)
        (only-in "./json-schema-node-validate.ss" poo-flow-json-schema-node-validate)
        (only-in "./json-schema-diagnostics.ss"
                 poo-flow-json-schema-validation-diagnostic-metadata))
(export SchemaContract. ProjectionContract. schema-value-contract)

;; Boolean membership shares the existing node evaluator; diagnosis retains
;; the original structured diagnostic and its precise nested instance path.
(define-type (SchemaContract. @ Type. identity node)
  .element?: (cut poo-flow-json-schema-node-valid? node <>)
  .diagnose:
  (lambda (value location)
    (map (lambda (diagnostic-value)
           (let (instance-path
                  (poo-flow-contract-object-ref
                    (poo-flow-json-schema-validation-diagnostic-metadata diagnostic-value)
                    'path location))
             (.o kind: 'schema-rejected path: instance-path diagnostic: diagnostic-value)))
         (poo-flow-json-schema-node-validate node value location))))

(def (schema-value-contract identity-value schema-value)
  (using (identity-value :~ symbol?)
    (let (normalization (poo-flow-json-schema-normalize schema-value))
      ;; Warnings/unsupported constraints may not silently weaken validation.
      (unless (null? (poo-flow-json-schema-normalization-diagnostics normalization))
        (error "Schema contains invalid or unsupported constraints" identity-value
               (poo-flow-json-schema-normalization-diagnostics normalization)))
      (.cc SchemaContract.
           'identity identity-value
           'node (poo-flow-json-schema-normalization-schema normalization)))))

;; Project the CURRENT value, never a captured parent. The original object is
;; returned by ordinary Type validation; projection is not normalization.
(define-type (ProjectionContract. @ Type. constraint project prepared-constraint .diagnose)
  prepared-constraint: (as-value-contract constraint)
  .element?: (lambda (value) (null? (.diagnose value '())))
  .diagnose:
  (lambda (value location)
    (unless (procedure? project) (error "Contract projection must be a procedure"))
    (diagnose prepared-constraint (project value) location)))
