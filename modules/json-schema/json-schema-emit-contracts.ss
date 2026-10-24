;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: emit Yuanxu object contracts from normalized JSON Schema IR.
;;; Optimization boundary: this module builds predicate closures once while
;;; emitting contracts; value validation reuses those closures without walking
;;; the normalized schema again.

(import (only-in :clan/poo/object
                 .alist
                 .ref
                 .slot?
                 object?)
        (only-in :std/text/pregexp
                 pregexp
                 pregexp-match)
        (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-contract-slot
                 yuanxu-contract-value-type
                 yuanxu-object-contract)
        (only-in :yuanxu/utilities/functional
                 yuanxu-all?
                 yuanxu-find
                 yuanxu-predicate-and
                 yuanxu-predicate-or
                 yuanxu-predicate-exactly-one)
        (only-in "./json-schema-constraints.ss"
                 yuanxu-json-schema-apply-node-constraints)
        (only-in "./functional.ss"
                 yuanxu-contract-key->string
                 yuanxu-contract-all?
                 yuanxu-contract-json-object?
                 yuanxu-contract-member?
                 yuanxu-contract-project-list
                 yuanxu-contract-filter-map)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node?
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-node->alist
                 yuanxu-json-schema-property-name
                 yuanxu-json-schema-property-schema
                 yuanxu-json-schema-property-required?
                 yuanxu-json-schema-property-doc
                 yuanxu-json-schema-property-metadata
                 yuanxu-json-schema-property->alist
                 yuanxu-json-schema-object?
                 yuanxu-json-schema-object-properties
                 yuanxu-json-schema-object-additional-properties
                 yuanxu-json-schema-object-pattern-properties
                 yuanxu-json-schema-object-metadata
                 yuanxu-json-schema-pattern-property?
                 yuanxu-json-schema-pattern-property->alist))


(import :yuanxu/modules/json-schema/json-schema-emit-runtime)

(export #t)

;; : (-> YuanxuJsonSchemaValue YuanxuJsonSchemaAlistValue)
(def (yuanxu-json-schema-map-value-schema->alist value)
  (case (cond
         ((yuanxu-json-schema-node? value) 'node)
         ((yuanxu-json-schema-pattern-property? value) 'pattern-property)
         ((pair? value) 'pair)
         (else 'literal))
   ((node)
    (yuanxu-json-schema-node->alist value))
   ((pattern-property)
    (yuanxu-json-schema-pattern-property->alist value))
   ((pair)
    (cons (yuanxu-json-schema-map-value-schema->alist (car value))
          (yuanxu-json-schema-map-value-schema->alist (cdr value))))
   (else value)))

;; yuanxu-json-schema-property->slot-contract
;;   : (-> YuanxuJsonSchemaProperty Symbol Symbol YuanxuSlotContract)
;;   | doc m%
;;       Emit one property contract while preserving normalized schema and source
;;       property metadata for later facts and receipts.
;;     %
(def (yuanxu-json-schema-property->slot-contract property object-key object-kind)
  (let* ((slot (yuanxu-json-schema-property-name property))
         (schema (yuanxu-json-schema-property-schema property))
         (metadata
          (append
           (list
            (cons 'source 'json-schema)
            (cons 'doc (yuanxu-json-schema-property-doc property))
            (cons 'schema (yuanxu-json-schema-node->alist schema))
            (cons 'property
                  (yuanxu-json-schema-property->alist property)))
           (yuanxu-json-schema-property-metadata property))))
    (yuanxu-contract-slot
     (yuanxu-json-schema-contract-key object-key slot)
     slot
     (yuanxu-contract-value-type
      (yuanxu-json-schema-node-value-kind schema)
      (yuanxu-json-schema-node-predicate schema)
      (yuanxu-json-schema-node-value-kind schema)
      (yuanxu-json-schema-node-predicate-key schema))
     (yuanxu-json-schema-property-required? property)
     metadata)))

;; yuanxu-json-schema-object-node->object-type-contract
;;   : (-> YuanxuJsonSchemaNode Symbol Symbol Symbol YuanxuObjectTypeContract)
;;   | doc m%
;;       Emit a structural object contract from a normalized object node.
;;     %
(def (yuanxu-json-schema-object-node->object-type-contract node owner object-kind
                                                             object-key)
  (let* ((object (yuanxu-json-schema-node-value node))
         (properties
          (if (yuanxu-json-schema-object? object)
            (yuanxu-json-schema-object-properties object)
            '()))
         (slots
          (map (lambda (property)
                 (yuanxu-json-schema-property->slot-contract
                  property object-key object-kind))
               properties))
         (metadata
          (append
           (list
            (cons 'source 'json-schema)
            (cons 'schema-kind 'object)
            (cons 'additional-properties
                  (yuanxu-json-schema-map-value-schema->alist
                   (yuanxu-json-schema-object-additional-properties object)))
            (cons 'pattern-properties
                  (yuanxu-json-schema-map-value-schema->alist
                   (yuanxu-json-schema-object-pattern-properties object)))
            (cons 'normalized-schema
                  (yuanxu-json-schema-node->alist node)))
           (yuanxu-json-schema-object-metadata object)
           (yuanxu-json-schema-node-metadata node))))
    (yuanxu-object-contract
     object-key
     owner
     object-kind
     object?
     slots
     metadata)))

;; yuanxu-json-schema-node->object-type-contract
;;   : (-> YuanxuJsonSchemaNode Symbol Symbol Symbol YuanxuObjectTypeContract)
;;   | doc m%
;;       Emit an object contract for structural schemas and a single `value`
;;       slot contract for scalar or fallback schemas.
;;     %
(def (yuanxu-json-schema-node->object-type-contract node owner object-kind
                                                      object-key)
  (case (and (yuanxu-json-schema-node? node)
             (yuanxu-json-schema-node-kind node))
    ((object)
     (yuanxu-json-schema-object-node->object-type-contract
      node
      owner
      object-kind
      object-key))
    (else
     (yuanxu-object-contract
      object-key
      owner
      object-kind
      object?
      (list
       (yuanxu-contract-slot
        (yuanxu-json-schema-contract-key object-key 'value)
        'value
        (yuanxu-contract-value-type
         (yuanxu-json-schema-node-value-kind node)
         (yuanxu-json-schema-node-predicate node)
         (yuanxu-json-schema-node-value-kind node)
         (yuanxu-json-schema-node-predicate-key node))
        #t
        (list
         (cons 'source 'json-schema)
         (cons 'schema (yuanxu-json-schema-node->alist node)))))
      (list
       (cons 'source 'json-schema)
       (cons 'schema-kind (yuanxu-json-schema-node-kind node))
       (cons 'normalized-schema (yuanxu-json-schema-node->alist node)))))))
