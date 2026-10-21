;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native Module System interface configuration. Product identity and policy are
;;; supplied by the caller; Core owns the schema index and option vocabulary.
(import (only-in :clan/poo/object .all-slots .o .ref .slot? object?)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/module-system/types ModuleAuthoringProfileContract))

(export yuanxu-module-kind=?
        yuanxu-module-object-ref/default
        yuanxu-module-object->alist
        yuanxu-module-interface-schema-index
        make-module-interface
        yuanxu-module-interface-id
        yuanxu-module-interface-schemas
        yuanxu-module-interface-schema-spec
        yuanxu-module-interface-authoring
        yuanxu-module-interface-metadata
        yuanxu-string-required
        yuanxu-string-constant
        yuanxu-string-default
        yuanxu-string-optional
        yuanxu-option-policy
        yuanxu-option-append
        yuanxu-option-override
        yuanxu-option-conflict)

(def (yuanxu-module-kind=? value expected)
  (cond
   ((and (string? value) (string? expected))
    (string=? value expected))
   (else (equal? value expected))))

(def (yuanxu-module-object-ref/default object slot-name default-value)
  (if (and (object? object) (.slot? object slot-name))
    (.ref object slot-name)
    default-value))

(def (yuanxu-module-object->alist/rev object slot-names rows-rev)
  (if (null? slot-names)
    rows-rev
    (yuanxu-module-object->alist/rev
     object (cdr slot-names)
     (cons (cons (car slot-names) (.ref object (car slot-names))) rows-rev))))

(def (yuanxu-module-object->alist value)
  (cond
   ((object? value)
    (reverse (yuanxu-module-object->alist/rev value (.all-slots value) '())))
   ((list? value) value)
   (else '())))

(def (yuanxu-module-interface-schema-index schema-object)
  (let (index (make-hash-table))
    (when (object? schema-object)
      (for-each
       (lambda (slot-name)
         (let (option-id
               (if (symbol? slot-name)
                 (symbol->string slot-name)
                 slot-name))
           (when (hash-key? index option-id)
             (error "duplicate normalized Module Interface schema id"
                    option-id))
           (hash-put! index option-id (.ref schema-object slot-name))))
       (.all-slots schema-object)))
    index))

(def (make-module-interface prototype interface-id-value schema-object
                            metadata-value authoring-value)
  (let (admitted-authoring
        (validate ModuleAuthoringProfileContract authoring-value))
    (.o (:: @ (list prototype))
        id: interface-id-value
        schemas: schema-object
        authoring: admitted-authoring
        metadata: metadata-value)))

(def (yuanxu-module-interface-id interface)
  (.ref interface 'id))

(def (yuanxu-module-interface-schemas interface)
  (.ref interface 'schemas))

(def (yuanxu-module-interface-schema-spec interface option-id)
  (let (index (.ref interface 'schema-index))
    (and (hash-table? index)
         (hash-get index option-id))))

(def (yuanxu-module-interface-authoring interface)
  (.ref interface 'authoring))

(def (yuanxu-module-interface-metadata interface)
  (.ref interface 'metadata))

(def (yuanxu-string-required)
  (.o type: 'String))

(def (yuanxu-string-constant constant-value)
  (.o type: 'String constant: constant-value))

(def (yuanxu-string-default default-value)
  (.o type: 'String default: default-value))

(def (yuanxu-string-optional)
  (.o type: 'String optional?: #t))

(def (yuanxu-option-policy value-type policy-rule default-value metadata-value)
  (.o type: value-type policy: policy-rule
      default: default-value metadata: metadata-value))

(def (yuanxu-option-append value-type default-value)
  (yuanxu-option-policy value-type 'append default-value '()))

(def (yuanxu-option-override value-type default-value)
  (yuanxu-option-policy value-type 'override default-value '()))

(def (yuanxu-option-conflict value-type)
  (.o type: value-type policy: 'conflict))
