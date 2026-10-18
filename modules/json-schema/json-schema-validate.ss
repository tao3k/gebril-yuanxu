;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: validate values through generated JSON Schema object contracts.
;;; Invariant: this owner checks emitted POO Flow contracts only. It is not a
;;; full JSON Schema evaluator and does not fetch schemas or run workflows.

(import (only-in :clan/poo/object object?)
        (only-in :clan/poo/mop element?)
        (only-in :core/module-system/schema/slot-contracts
                 poo-flow-contract-slot-name
                 poo-flow-contract-slot-required?
                 poo-flow-contract-slot-type
                 poo-flow-contract-slot->alist
                 poo-flow-native-contract-key
                 poo-flow-native-contract-slots)
        (only-in "./functional.ss"
                 poo-flow-contract-any?
                 poo-flow-contract-json-object?
                 poo-flow-contract-project-list
                 poo-flow-contract-filter-map)
        (only-in "./json-schema-ir.ss" poo-flow-json-schema-normalization-schema)
        (only-in "./json-schema-receipt.ss"
                 poo-flow-json-schema-contract-artifact-normalization
                 poo-flow-json-schema-contract-artifact-object-contract)
        (only-in "./json-schema-validation-core.ss"
                 +poo-flow-json-schema-validation-missing+
                 poo-flow-json-schema-candidate-slot)
        (only-in "./json-schema-valid.ss" poo-flow-json-schema-node-valid?)
        "./json-schema-diagnostics.ss"
        "./json-schema-node-validate.ss")

(export make-poo-flow-json-schema-validation-diagnostic
        poo-flow-json-schema-validation-diagnostic?
        poo-flow-json-schema-validation-diagnostic-severity
        poo-flow-json-schema-validation-diagnostic-reason
        poo-flow-json-schema-validation-diagnostic-message
        poo-flow-json-schema-validation-diagnostic-slot
        poo-flow-json-schema-validation-diagnostic-value
        poo-flow-json-schema-validation-diagnostic-contract
        poo-flow-json-schema-validation-diagnostic-metadata
        poo-flow-json-schema-validation-diagnostic->alist
        make-poo-flow-json-schema-object-contract-validation
        poo-flow-json-schema-object-contract-validation?
        poo-flow-json-schema-object-contract-validation-kind
        poo-flow-json-schema-object-contract-validation-schema
        poo-flow-json-schema-object-contract-validation-object-key
        poo-flow-json-schema-object-contract-validation-valid?
        poo-flow-json-schema-object-contract-validation-diagnostics
        poo-flow-json-schema-object-contract-validation-checked-slots
        poo-flow-json-schema-object-contract-validation-missing-required
        poo-flow-json-schema-object-contract-validation-invalid-slots
        poo-flow-json-schema-object-contract-validation-runtime-executed
        poo-flow-json-schema-object-contract-validation->alist
        poo-flow-json-schema-node-validate
        poo-flow-json-schema-node-valid?
        poo-flow-json-schema-contract-artifact-value-valid?
        poo-flow-json-schema-contract-artifact-validate
        poo-flow-json-schema-object-contract-validate)


;;; Boundary: validation receipts store typed diagnostics internally and
;;; project to bounded alists at the handoff boundary.
;; : (-> Symbol String Symbol Boolean [Diagnostic] [Symbol] [Symbol] [Symbol] Boolean PooFlowJsonSchemaObjectContractValidation)
(defstruct poo-flow-json-schema-object-contract-validation
  (kind
   schema
   object-key
   valid?
   diagnostics
   checked-slots
   missing-required
   invalid-slots
   runtime-executed)
  transparent: #t)

;; : (-> PooFlowSlotContract JsonSchemaCandidateObject PooFlowJsonSchemaValidationDiagnostic)
(def (poo-flow-json-schema-missing-required-diagnostic slot-contract candidate)
  (make-poo-flow-json-schema-validation-diagnostic
   'error
   'missing-required-slot
   "Required JSON Schema contract slot is missing"
   (poo-flow-contract-slot-name slot-contract)
   candidate
   (poo-flow-contract-slot->alist slot-contract)
   '((owner . json-schema-validate))))


;; : (-> PooFlowSlotContract JsonSchemaCandidateSlotValue PooFlowJsonSchemaValidationDiagnostic)
(def (poo-flow-json-schema-invalid-slot-diagnostic slot-contract value)
  (make-poo-flow-json-schema-validation-diagnostic
   'error
   'invalid-slot-value
   "JSON Schema contract slot predicate rejected the value"
   (poo-flow-contract-slot-name slot-contract)
   value
   (poo-flow-contract-slot->alist slot-contract)
   '((owner . json-schema-validate))))


;; : (-> JsonSchemaCandidateObject PooFlowJsonSchemaValidationDiagnostic)
(def (poo-flow-json-schema-invalid-object-diagnostic candidate)
  (make-poo-flow-json-schema-validation-diagnostic
   'error
   'invalid-object-shape
   "JSON Schema object-contract validation requires a POO object or alist"
   #f
   candidate
   '()
   '((owner . json-schema-validate))))


;; : (-> PooFlowSlotContract JsonSchemaCandidateObject MaybeDiagnostic)
(def (poo-flow-json-schema-validate-slot slot-contract candidate)
  (let (value
        (poo-flow-json-schema-candidate-slot
         candidate
         (poo-flow-contract-slot-name slot-contract)))
    (cond
     ((eq? value +poo-flow-json-schema-validation-missing+)
      (and (poo-flow-contract-slot-required? slot-contract)
           (poo-flow-json-schema-missing-required-diagnostic
            slot-contract
            candidate)))
     ((element? (poo-flow-contract-slot-type slot-contract) value)
      #f)
     (else
      (poo-flow-json-schema-invalid-slot-diagnostic
       slot-contract
       value)))))

;; : (-> [PooFlowJsonSchemaValidationDiagnostic] Symbol [Symbol])
(def (poo-flow-json-schema-validation-slots-by-reason diagnostics reason)
  (poo-flow-contract-filter-map
   (lambda (diagnostic)
     (and (eq? (poo-flow-json-schema-validation-diagnostic-reason diagnostic)
               reason)
          (poo-flow-json-schema-validation-diagnostic-slot diagnostic)))
   diagnostics))

;; : (-> PooFlowJsonSchemaValidationDiagnostic Boolean)
(def (poo-flow-json-schema-validation-fatal? diagnostic)
  (let (severity
        (poo-flow-json-schema-validation-diagnostic-severity diagnostic))
    (or (eq? severity 'error)
        (eq? severity 'fatal))))

;; : (-> [PooFlowJsonSchemaValidationDiagnostic] Boolean)
(def (poo-flow-json-schema-validation-diagnostics-valid? diagnostics)
  (not
   (poo-flow-contract-any?
    poo-flow-json-schema-validation-fatal?
    diagnostics)))

;; : (-> PooFlowJsonSchemaObjectContractValidation Alist)
(def (poo-flow-json-schema-object-contract-validation->alist validation)
  (list
   (cons 'kind
         (poo-flow-json-schema-object-contract-validation-kind validation))
   (cons 'schema
         (poo-flow-json-schema-object-contract-validation-schema validation))
   (cons 'object-key
         (poo-flow-json-schema-object-contract-validation-object-key validation))
   (cons 'valid?
         (poo-flow-json-schema-object-contract-validation-valid? validation))
   (cons 'diagnostics
         (poo-flow-contract-project-list
          poo-flow-json-schema-validation-diagnostic->alist
          (poo-flow-json-schema-object-contract-validation-diagnostics validation)))
   (cons 'diagnostic-count
         (length
          (poo-flow-json-schema-object-contract-validation-diagnostics
           validation)))
   (cons 'checked-slots
         (poo-flow-json-schema-object-contract-validation-checked-slots
          validation))
   (cons 'missing-required
         (poo-flow-json-schema-object-contract-validation-missing-required
          validation))
   (cons 'invalid-slots
         (poo-flow-json-schema-object-contract-validation-invalid-slots
          validation))
   (cons 'runtime-executed
         (poo-flow-json-schema-object-contract-validation-runtime-executed
          validation))))

;; : (-> PooFlowObjectTypeContract [Diagnostic] PooFlowJsonSchemaObjectContractValidation)
(def (poo-flow-json-schema-validation-receipt object-contract diagnostics)
  (let (slots (poo-flow-native-contract-slots object-contract))
    (make-poo-flow-json-schema-object-contract-validation
     'json-schema-object-contract-validation
     "poo-flow-json-schema-object-contract-validation/v1"
     (poo-flow-native-contract-key object-contract)
     (poo-flow-json-schema-validation-diagnostics-valid? diagnostics)
     diagnostics
     (poo-flow-contract-project-list
      poo-flow-contract-slot-name
      slots)
     (poo-flow-json-schema-validation-slots-by-reason
      diagnostics
      'missing-required-slot)
     (append
      (poo-flow-json-schema-validation-slots-by-reason
       diagnostics
       'invalid-slot-value)
      (poo-flow-json-schema-validation-slots-by-reason
       diagnostics
       'invalid-node-value)
      (poo-flow-json-schema-validation-slots-by-reason
       diagnostics
       'additional-property-not-allowed))
     #f)))

;; : (-> PooFlowObjectTypeContract JsonSchemaCandidateObject PooFlowJsonSchemaObjectContractValidation)
(def (poo-flow-json-schema-object-contract-validate object-contract candidate)
  (let* ((slots
          (poo-flow-native-contract-slots object-contract))
         (shape-diagnostics
          (if (or (hash-table? candidate)
                  (poo-flow-contract-json-object? candidate)
                  (object? candidate))
            '()
            (list
             (poo-flow-json-schema-invalid-object-diagnostic candidate))))
         (slot-diagnostics
          (if (null? shape-diagnostics)
            (poo-flow-contract-filter-map
             (lambda (slot-contract)
               (poo-flow-json-schema-validate-slot
                slot-contract
                candidate))
             slots)
            '()))
         (diagnostics
          (append shape-diagnostics slot-diagnostics)))
    (poo-flow-json-schema-validation-receipt object-contract diagnostics)))

;; : (-> PooFlowJsonSchemaContractArtifact JsonSchemaCandidateObject PooFlowJsonSchemaObjectContractValidation)
(def (poo-flow-json-schema-contract-artifact-validate artifact candidate)
  (let* ((object-contract
          (poo-flow-json-schema-contract-artifact-object-contract artifact))
         (root-node
         (poo-flow-json-schema-normalization-schema
          (poo-flow-json-schema-contract-artifact-normalization artifact)))
        (shape-diagnostics
          (if (or (hash-table? candidate)
                  (poo-flow-contract-json-object? candidate)
                  (object? candidate))
            '()
            (list
             (poo-flow-json-schema-invalid-object-diagnostic candidate))))
         (diagnostics
          (if (null? shape-diagnostics)
            (if (poo-flow-json-schema-node-valid? root-node candidate)
              '()
              (poo-flow-json-schema-node-validate root-node candidate '()))
            shape-diagnostics)))
    (poo-flow-json-schema-validation-receipt
     object-contract
     diagnostics)))

;; Receipt-specific predicate stays with the receipt consumer.
(def (poo-flow-json-schema-contract-artifact-value-valid? artifact candidate)
  (and (or (hash-table? candidate)
           (poo-flow-contract-json-object? candidate)
           (object? candidate))
       (poo-flow-json-schema-node-valid?
        (poo-flow-json-schema-normalization-schema
         (poo-flow-json-schema-contract-artifact-normalization artifact))
        candidate)))
