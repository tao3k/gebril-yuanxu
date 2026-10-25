;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Core POO values for Module option configuration, schema, and validation.
;;; Product descriptors decide how these values are projected and presented.

(import (only-in :yuanxu/object-family/syntax defpoo-object-family)
        (only-in :clan/poo/object .cc .ref .slot? object<-alist)
        (only-in :clan/poo/type Record))

(export yuanxu-module-option-config-prototype
        make-yuanxu-module-option-config
        yuanxu-module-option-config?
        yuanxu-module-option-config-id
        yuanxu-module-option-config-value
        yuanxu-module-option-config-source-module
        yuanxu-module-option-config-metadata
        yuanxu-module-option-schema-prototype
        make-yuanxu-module-option-schema
        yuanxu-module-option-schema?
        yuanxu-module-option-schema-id
        yuanxu-module-option-schema-source-module
        yuanxu-module-option-schema-field
        yuanxu-module-option-schema-contract
        yuanxu-module-option-schema-type
        yuanxu-module-option-schema-rule
        yuanxu-module-option-schema-value
        yuanxu-module-option-schema-metadata
        yuanxu-module-option-validation-receipt-prototype
        make-yuanxu-module-option-validation-receipt
        yuanxu-module-option-validation-receipt?
        yuanxu-module-option-validation-receipt-id
        yuanxu-module-option-validation-receipt-source-module
        yuanxu-module-option-validation-receipt-valid?
        yuanxu-module-option-validation-receipt-code
        yuanxu-module-option-validation-receipt-messages
        yuanxu-module-option-validation-receipt-metadata)

(defpoo-object-family
  (prototype yuanxu-module-option-config-prototype
             option-config?
             yuanxu-module-option-config?)
  (constructor make-yuanxu-module-option-config
               (id-value id)
               (option-value value)
               (source-module-value source-module)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-option-config-id id)
   (yuanxu-module-option-config-value value)
   (yuanxu-module-option-config-source-module source-module)
   (yuanxu-module-option-config-metadata metadata))
  (projections))

(defpoo-object-family
  (prototype yuanxu-module-option-schema-prototype
             option-schema?
             yuanxu-module-option-schema?)
  (constructor make-yuanxu-module-option-schema
               (id-value id)
               (source-module-value source-module)
               (field-value field)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-option-schema-id id)
   (yuanxu-module-option-schema-source-module source-module)
   (yuanxu-module-option-schema-field field)
   (yuanxu-module-option-schema-metadata metadata))
  (projections))

;; Reporting projections read the native effective Slot, never a shadow type DSL.
(def (yuanxu-module-option-schema-type schema)
  (.ref (yuanxu-module-option-schema-field schema) 'type))
(def (yuanxu-module-option-schema-rule schema)
  (let (field (yuanxu-module-option-schema-field schema))
    (cond ((.slot? field 'policy) (.ref field 'policy))
          ((.slot? field 'constant) 'constant)
          ((.slot? field 'default) 'default)
          ((.ref field 'optional) 'optional)
          (else 'required))))
(def (yuanxu-module-option-schema-value schema)
  (let (field (yuanxu-module-option-schema-field schema))
    (cond ((.slot? field 'constant) (.ref field 'constant))
          ((.slot? field 'default) (.ref field 'default))
          (else #f))))

(def (yuanxu-module-option-schema-contract schema)
  (.cc (Record) 'slots
    (object<-alist
      (list (cons (string->symbol (yuanxu-module-option-schema-id schema))
                  (yuanxu-module-option-schema-field schema))))))

(defpoo-object-family
  (prototype yuanxu-module-option-validation-receipt-prototype
             option-validation-receipt?
             yuanxu-module-option-validation-receipt?)
  (constructor make-yuanxu-module-option-validation-receipt
               (id-value id)
               (source-module-value source-module)
               (valid-value valid?)
               (code-value code)
               (messages-value messages)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-option-validation-receipt-id id)
   (yuanxu-module-option-validation-receipt-source-module source-module)
   (yuanxu-module-option-validation-receipt-valid? valid?)
   (yuanxu-module-option-validation-receipt-code code)
   (yuanxu-module-option-validation-receipt-messages messages)
   (yuanxu-module-option-validation-receipt-metadata metadata))
  (projections))
