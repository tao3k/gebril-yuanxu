;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Core POO values for Module option configuration, schema, and validation.
;;; Product descriptors decide how these values are projected and presented.

(import (only-in :clan/poo/object .cc .ref .slot? object<-alist)
        (only-in :clan/poo/type Record String Symbol Or)
        (only-in :clan/poo/mop define-type Slot))

(export ModuleOptionSchema
        yuanxu-module-option-schema-contract
        yuanxu-module-option-schema-rule
        yuanxu-module-option-schema-value
        yuanxu-module-option-schema-metadata)

;; Keep the effective Slot itself, rather than copying its Type/default/policy.
(define-type ModuleOptionSchema
  (Record id: [String]
          source-module: [(Or String Symbol)]
          field: [Slot]))

;; Reporting projections read the native effective Slot, never a shadow type DSL.
(def (yuanxu-module-option-schema-rule schema)
  (let (field (.ref schema 'field))
    (cond ((.slot? field 'policy) (.ref field 'policy))
          ((.slot? field 'constant) 'constant)
          ((.slot? field 'default) 'default)
          ((.ref field 'optional) 'optional)
          (else 'required))))
(def (yuanxu-module-option-schema-value schema)
  (let (field (.ref schema 'field))
    (cond ((.slot? field 'constant) (.ref field 'constant))
          ((.slot? field 'default) (.ref field 'default))
          (else #f))))

;; Diagnostic annotations remain owned by the effective Slot.
(def (yuanxu-module-option-schema-metadata schema)
  (let (field (.ref schema 'field))
    (if (.slot? field 'metadata) (.ref field 'metadata) '())))

(def (yuanxu-module-option-schema-contract schema)
  (.cc (Record) 'slots
    (object<-alist
      (list (cons (string->symbol (.ref schema 'id))
                  (.ref schema 'field))))))
