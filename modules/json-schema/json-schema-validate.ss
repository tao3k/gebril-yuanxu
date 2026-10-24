;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: validate values through generated JSON Schema object contracts.
;;; Invariant: this owner checks emitted Yuanxu contracts only. It is not a
;;; full JSON Schema evaluator and does not fetch schemas or run workflows.

(import (only-in :clan/poo/object object?)
        (only-in :clan/poo/mop element?)
        (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-contract-slot-name
                 yuanxu-contract-slot-required?
                 yuanxu-contract-slot-type
                 yuanxu-contract-slot->alist
                 yuanxu-object-contract-key
                 yuanxu-object-contract-slots)
        (only-in "./functional.ss"
                 yuanxu-contract-any?
                 yuanxu-contract-json-object?
                 yuanxu-contract-project-list
                 yuanxu-contract-filter-map)
        (only-in "./json-schema-ir.ss" yuanxu-json-schema-normalization-schema)
        (only-in "./json-schema-receipt.ss"
                 yuanxu-json-schema-contract-artifact-normalization
                 yuanxu-json-schema-contract-artifact-object-contract)
        (only-in "./json-schema-validation-core.ss"
                 +yuanxu-json-schema-validation-missing+
                 yuanxu-json-schema-candidate-slot)
        (only-in "./json-schema-valid.ss" yuanxu-json-schema-node-valid?)
        "./json-schema-diagnostics.ss"
        "./json-schema-node-validate.ss")

(export make-yuanxu-json-schema-validation-diagnostic
        yuanxu-json-schema-validation-diagnostic?
        yuanxu-json-schema-validation-diagnostic-severity
        yuanxu-json-schema-validation-diagnostic-reason
        yuanxu-json-schema-validation-diagnostic-message
        yuanxu-json-schema-validation-diagnostic-slot
        yuanxu-json-schema-validation-diagnostic-value
        yuanxu-json-schema-validation-diagnostic-contract
        yuanxu-json-schema-validation-diagnostic-metadata
        yuanxu-json-schema-validation-diagnostic->alist
        make-yuanxu-json-schema-object-contract-validation
        yuanxu-json-schema-object-contract-validation?
        yuanxu-json-schema-object-contract-validation-kind
        yuanxu-json-schema-object-contract-validation-schema
        yuanxu-json-schema-object-contract-validation-object-key
        yuanxu-json-schema-object-contract-validation-valid?
        yuanxu-json-schema-object-contract-validation-diagnostics
        yuanxu-json-schema-object-contract-validation-checked-slots
        yuanxu-json-schema-object-contract-validation-missing-required
        yuanxu-json-schema-object-contract-validation-invalid-slots
        yuanxu-json-schema-object-contract-validation-runtime-executed
        yuanxu-json-schema-object-contract-validation->alist
        yuanxu-json-schema-node-validate
        yuanxu-json-schema-node-valid?
        yuanxu-json-schema-contract-artifact-value-valid?
        yuanxu-json-schema-contract-artifact-validate
        yuanxu-json-schema-object-contract-validate)


;;; Boundary: validation receipts store typed diagnostics internally and
;;; project to bounded alists at the handoff boundary.
;; : (-> Symbol String Symbol Boolean [Diagnostic] [Symbol] [Symbol] [Symbol] Boolean YuanxuJsonSchemaObjectContractValidation)
(defstruct yuanxu-json-schema-object-contract-validation
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

;; : (-> YuanxuSlotContract JsonSchemaCandidateObject YuanxuJsonSchemaValidationDiagnostic)
(def (yuanxu-json-schema-missing-required-diagnostic slot-contract candidate)
  (make-yuanxu-json-schema-validation-diagnostic
   'error
   'missing-required-slot
   "Required JSON Schema contract slot is missing"
   (yuanxu-contract-slot-name slot-contract)
   candidate
   (yuanxu-contract-slot->alist slot-contract)
   '((owner . json-schema-validate))))


;; : (-> YuanxuSlotContract JsonSchemaCandidateSlotValue YuanxuJsonSchemaValidationDiagnostic)
(def (yuanxu-json-schema-invalid-slot-diagnostic slot-contract value)
  (make-yuanxu-json-schema-validation-diagnostic
   'error
   'invalid-slot-value
   "JSON Schema contract slot predicate rejected the value"
   (yuanxu-contract-slot-name slot-contract)
   value
   (yuanxu-contract-slot->alist slot-contract)
   '((owner . json-schema-validate))))


;; : (-> JsonSchemaCandidateObject YuanxuJsonSchemaValidationDiagnostic)
(def (yuanxu-json-schema-invalid-object-diagnostic candidate)
  (make-yuanxu-json-schema-validation-diagnostic
   'error
   'invalid-object-shape
   "JSON Schema object-contract validation requires a POO object or alist"
   #f
   candidate
   '()
   '((owner . json-schema-validate))))


;; : (-> YuanxuSlotContract JsonSchemaCandidateObject MaybeDiagnostic)
(def (yuanxu-json-schema-validate-slot slot-contract candidate)
  (let (value
        (yuanxu-json-schema-candidate-slot
         candidate
         (yuanxu-contract-slot-name slot-contract)))
    (cond
     ((eq? value +yuanxu-json-schema-validation-missing+)
      (and (yuanxu-contract-slot-required? slot-contract)
           (yuanxu-json-schema-missing-required-diagnostic
            slot-contract
            candidate)))
     ((element? (yuanxu-contract-slot-type slot-contract) value)
      #f)
     (else
      (yuanxu-json-schema-invalid-slot-diagnostic
       slot-contract
       value)))))

;; : (-> [YuanxuJsonSchemaValidationDiagnostic] Symbol [Symbol])
(def (yuanxu-json-schema-validation-slots-by-reason diagnostics reason)
  (yuanxu-contract-filter-map
   (lambda (diagnostic)
     (and (eq? (yuanxu-json-schema-validation-diagnostic-reason diagnostic)
               reason)
          (yuanxu-json-schema-validation-diagnostic-slot diagnostic)))
   diagnostics))

;; : (-> YuanxuJsonSchemaValidationDiagnostic Boolean)
(def (yuanxu-json-schema-validation-fatal? diagnostic)
  (let (severity
        (yuanxu-json-schema-validation-diagnostic-severity diagnostic))
    (or (eq? severity 'error)
        (eq? severity 'fatal))))

;; : (-> [YuanxuJsonSchemaValidationDiagnostic] Boolean)
(def (yuanxu-json-schema-validation-diagnostics-valid? diagnostics)
  (not
   (yuanxu-contract-any?
    yuanxu-json-schema-validation-fatal?
    diagnostics)))

;; : (-> YuanxuJsonSchemaObjectContractValidation Alist)
(def (yuanxu-json-schema-object-contract-validation->alist validation)
  (list
   (cons 'kind
         (yuanxu-json-schema-object-contract-validation-kind validation))
   (cons 'schema
         (yuanxu-json-schema-object-contract-validation-schema validation))
   (cons 'object-key
         (yuanxu-json-schema-object-contract-validation-object-key validation))
   (cons 'valid?
         (yuanxu-json-schema-object-contract-validation-valid? validation))
   (cons 'diagnostics
         (yuanxu-contract-project-list
          yuanxu-json-schema-validation-diagnostic->alist
          (yuanxu-json-schema-object-contract-validation-diagnostics validation)))
   (cons 'diagnostic-count
         (length
          (yuanxu-json-schema-object-contract-validation-diagnostics
           validation)))
   (cons 'checked-slots
         (yuanxu-json-schema-object-contract-validation-checked-slots
          validation))
   (cons 'missing-required
         (yuanxu-json-schema-object-contract-validation-missing-required
          validation))
   (cons 'invalid-slots
         (yuanxu-json-schema-object-contract-validation-invalid-slots
          validation))
   (cons 'runtime-executed
         (yuanxu-json-schema-object-contract-validation-runtime-executed
          validation))))

;; : (-> YuanxuObjectTypeContract [Diagnostic] YuanxuJsonSchemaObjectContractValidation)
(def (yuanxu-json-schema-validation-receipt object-contract diagnostics)
  (let (slots (yuanxu-object-contract-slots object-contract))
    (make-yuanxu-json-schema-object-contract-validation
     'json-schema-object-contract-validation
     "yuanxu-json-schema-object-contract-validation/v1"
     (yuanxu-object-contract-key object-contract)
     (yuanxu-json-schema-validation-diagnostics-valid? diagnostics)
     diagnostics
     (yuanxu-contract-project-list
      yuanxu-contract-slot-name
      slots)
     (yuanxu-json-schema-validation-slots-by-reason
      diagnostics
      'missing-required-slot)
     (append
      (yuanxu-json-schema-validation-slots-by-reason
       diagnostics
       'invalid-slot-value)
      (yuanxu-json-schema-validation-slots-by-reason
       diagnostics
       'invalid-node-value)
      (yuanxu-json-schema-validation-slots-by-reason
       diagnostics
       'additional-property-not-allowed))
     #f)))

;; : (-> YuanxuObjectTypeContract JsonSchemaCandidateObject YuanxuJsonSchemaObjectContractValidation)
(def (yuanxu-json-schema-object-contract-validate object-contract candidate)
  (let* ((slots
          (yuanxu-object-contract-slots object-contract))
         (shape-diagnostics
          (if (or (hash-table? candidate)
                  (yuanxu-contract-json-object? candidate)
                  (object? candidate))
            '()
            (list
             (yuanxu-json-schema-invalid-object-diagnostic candidate))))
         (slot-diagnostics
          (if (null? shape-diagnostics)
            (yuanxu-contract-filter-map
             (lambda (slot-contract)
               (yuanxu-json-schema-validate-slot
                slot-contract
                candidate))
             slots)
            '()))
         (diagnostics
          (append shape-diagnostics slot-diagnostics)))
    (yuanxu-json-schema-validation-receipt object-contract diagnostics)))

;; : (-> YuanxuJsonSchemaContractArtifact JsonSchemaCandidateObject YuanxuJsonSchemaObjectContractValidation)
(def (yuanxu-json-schema-contract-artifact-validate artifact candidate)
  (let* ((object-contract
          (yuanxu-json-schema-contract-artifact-object-contract artifact))
         (root-node
         (yuanxu-json-schema-normalization-schema
          (yuanxu-json-schema-contract-artifact-normalization artifact)))
        (shape-diagnostics
          (if (or (hash-table? candidate)
                  (yuanxu-contract-json-object? candidate)
                  (object? candidate))
            '()
            (list
             (yuanxu-json-schema-invalid-object-diagnostic candidate))))
         (diagnostics
          (if (null? shape-diagnostics)
            (if (yuanxu-json-schema-node-valid? root-node candidate)
              '()
              (yuanxu-json-schema-node-validate root-node candidate '()))
            shape-diagnostics)))
    (yuanxu-json-schema-validation-receipt
     object-contract
     diagnostics)))

;; Receipt-specific predicate stays with the receipt consumer.
(def (yuanxu-json-schema-contract-artifact-value-valid? artifact candidate)
  (and (or (hash-table? candidate)
           (yuanxu-contract-json-object? candidate)
           (object? candidate))
       (yuanxu-json-schema-node-valid?
        (yuanxu-json-schema-normalization-schema
         (yuanxu-json-schema-contract-artifact-normalization artifact))
        candidate)))
