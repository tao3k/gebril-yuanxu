;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure recursive node validation; no admission, receipts, or Core descriptors.
(import (only-in "./functional.ss"
                 poo-flow-contract-append-map
                 poo-flow-contract-json-object?
                 poo-flow-contract-project-list
                 poo-flow-contract-member?)
        (only-in "./json-schema-ir.ss"
                 poo-flow-json-schema-node?
                 poo-flow-json-schema-node-kind
                 poo-flow-json-schema-node-value
                 poo-flow-json-schema-node->alist
                 poo-flow-json-schema-property-name
                 poo-flow-json-schema-property-schema
                 poo-flow-json-schema-property-required?
                 poo-flow-json-schema-property->alist
                 poo-flow-json-schema-object-properties
                 poo-flow-json-schema-object-additional-properties
                 poo-flow-json-schema-object-pattern-properties
                 poo-flow-json-schema-pattern-property-schema)
        (only-in "./json-schema-values.ss" poo-flow-json-schema-null?)
        (only-in "./json-schema-validation-core.ss"
                 +poo-flow-json-schema-validation-missing+
                 poo-flow-json-schema-candidate-slot
                 poo-flow-json-schema-candidate-rows
                 poo-flow-json-schema-path-append
                 poo-flow-json-schema-schema-guided-array-values
                 poo-flow-json-schema-array-node-shape-valid?
                 poo-flow-json-schema-object-node-shape-valid?
                 poo-flow-json-schema-row-key-symbol
                 poo-flow-json-schema-row-key-string
                 poo-flow-json-schema-matching-pattern-properties)
        (only-in "./json-schema-valid.ss"
                 poo-flow-json-schema-node-valid?))
(import "./json-schema-diagnostics.ss")
(export poo-flow-json-schema-node-validate)

(def (poo-flow-json-schema-nullable-branch node)
  (and (eq? (poo-flow-json-schema-node-kind node) 'any-of)
       (let (children (poo-flow-json-schema-node-value node))
         (and (= (length children) 2)
              (cond
               ((eq? (poo-flow-json-schema-node-kind (car children)) 'null) (cadr children))
               ((eq? (poo-flow-json-schema-node-kind (cadr children)) 'null) (car children))
               (else #f))))))

(def (poo-flow-json-schema-node-validate node value path)
  (let (kind (poo-flow-json-schema-node-kind node))
    (cond
     ((poo-flow-json-schema-nullable-branch node)
      (if (poo-flow-json-schema-null? value) '()
        (poo-flow-json-schema-node-validate
          (poo-flow-json-schema-nullable-branch node) value path)))
     ((and (eq? kind 'array)
           (not (poo-flow-json-schema-array-node-shape-valid? node value)))
      (list
       (poo-flow-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive array predicate rejected the value"
        path
        value
        (poo-flow-json-schema-node->alist node))))
     ((and (eq? kind 'object)
           (not (poo-flow-json-schema-object-node-shape-valid? node value)))
      (list
       (poo-flow-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive object predicate rejected the value"
        path
        value
        (poo-flow-json-schema-node->alist node))))
     ((and (eq? kind 'one-of)
           (= (length (poo-flow-json-schema-node-value node)) 1))
      (poo-flow-json-schema-node-validate
       (car (poo-flow-json-schema-node-value node))
       value
       path))
     ((and (not (eq? kind 'array))
           (not (eq? kind 'object))
           (not (poo-flow-json-schema-node-valid? node value)))
      (list
       (poo-flow-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive node predicate rejected the value"
        path
        value
        (poo-flow-json-schema-node->alist node))))
     (else
      (cond
       ((eq? kind 'object)
        (poo-flow-json-schema-object-node-validate node value path))
       ((eq? kind 'array)
        (poo-flow-json-schema-array-node-validate node value path))
       ((and (eq? kind 'nullable)
             (not (poo-flow-json-schema-null? value)))
        (poo-flow-json-schema-node-validate
         (poo-flow-json-schema-node-value node)
         value
         path))
       (else '()))))))

(def (poo-flow-json-schema-array-node-validate node value path)
  (let ((item-node (poo-flow-json-schema-node-value node))
        (items (poo-flow-json-schema-schema-guided-array-values value)))
    (poo-flow-contract-append-map
     (lambda (indexed-item)
       (if (and (list? item-node) (>= (cdr indexed-item) (length item-node)))
         '()
         (poo-flow-json-schema-node-validate
        (if (list? item-node) (list-ref item-node (cdr indexed-item)) item-node)
        (car indexed-item)
        (poo-flow-json-schema-path-append path (cdr indexed-item)))))
     (map cons items (iota (length items))))))

(def (poo-flow-json-schema-property-validate property candidate path)
  (let* ((slot
          (poo-flow-json-schema-property-name property))
         (value
          (poo-flow-json-schema-candidate-slot candidate slot))
         (slot-path
          (poo-flow-json-schema-path-append path slot)))
    (cond
     ((eq? value +poo-flow-json-schema-validation-missing+)
      (if (poo-flow-json-schema-property-required? property)
        (list
         (poo-flow-json-schema-missing-path-diagnostic
          slot-path
          candidate
          (poo-flow-json-schema-property->alist property)))
        '()))
     (else
      (poo-flow-json-schema-node-validate
       (poo-flow-json-schema-property-schema property)
       value
       slot-path)))))

(def (poo-flow-json-schema-validation-row-value object-row)
  (let (tail (cdr object-row))
    (if (and (pair? tail)
             (null? (cdr tail))
             (not (poo-flow-contract-json-object? tail))
             (poo-flow-contract-json-object? (car tail)))
      (car tail)
      tail)))

(def (poo-flow-json-schema-pattern-row-validate pattern-property object-row path)
  (poo-flow-json-schema-node-validate
   (poo-flow-json-schema-pattern-property-schema pattern-property)
   (poo-flow-json-schema-validation-row-value object-row)
   (poo-flow-json-schema-path-append
    path
    (poo-flow-json-schema-row-key-symbol object-row))))

(def (poo-flow-json-schema-additional-property-validate additional object-row
                                                        path)
  (let ((row-path
         (poo-flow-json-schema-path-append
          path
          (poo-flow-json-schema-row-key-symbol object-row))))
    (cond
     ((eq? additional 'unspecified) '())
     ((eq? additional #t) [])
     ((eq? additional #f)
      (list
       (poo-flow-json-schema-invalid-path-diagnostic
        'additional-property-not-allowed
        "JSON Schema additionalProperties rejected object key"
        row-path
        (poo-flow-json-schema-validation-row-value object-row)
        additional)))
     ((and (poo-flow-json-schema-node? additional)
           (eq? (poo-flow-json-schema-node-kind additional) 'never))
      (list
       (poo-flow-json-schema-invalid-path-diagnostic
        'additional-property-not-allowed
        "JSON Schema additionalProperties rejected the object key"
        row-path
     (poo-flow-json-schema-validation-row-value object-row)
        (poo-flow-json-schema-node->alist additional))))
     ((poo-flow-json-schema-node? additional)
    (poo-flow-json-schema-node-validate
     additional
     (poo-flow-json-schema-validation-row-value object-row)
     row-path))
     (else '()))))

(def (poo-flow-json-schema-object-row-validate object object-row declared
                                               path)
  (let* ((row-key
          (poo-flow-json-schema-row-key-symbol object-row))
         (row-key-string
          (poo-flow-json-schema-row-key-string object-row))
         (pattern-matches
          (poo-flow-json-schema-matching-pattern-properties
           (poo-flow-json-schema-object-pattern-properties object)
           row-key-string))
         (pattern-diagnostics
          (poo-flow-contract-append-map
           (lambda (pattern-row)
             (poo-flow-json-schema-pattern-row-validate
              pattern-row
              object-row
              path))
           pattern-matches)))
    (append
     pattern-diagnostics
     (if (or (poo-flow-contract-member? row-key declared)
             (not (null? pattern-matches)))
       '()
       (poo-flow-json-schema-additional-property-validate
        (poo-flow-json-schema-object-additional-properties object)
        object-row
        path)))))

(def (poo-flow-json-schema-object-node-validate node candidate path)
  (let* ((object
          (poo-flow-json-schema-node-value node))
         (properties
          (poo-flow-json-schema-object-properties object))
         (declared
          (poo-flow-contract-project-list
           poo-flow-json-schema-property-name
           properties))
         (property-diagnostics
          (poo-flow-contract-append-map
           (lambda (property)
             (poo-flow-json-schema-property-validate
              property
              candidate
              path))
           properties))
         (map-diagnostics
          (poo-flow-contract-append-map
           (lambda (row)
             (poo-flow-json-schema-object-row-validate
              object
              row
              declared
              path))
           (poo-flow-json-schema-candidate-rows candidate))))
    (append property-diagnostics map-diagnostics)))
