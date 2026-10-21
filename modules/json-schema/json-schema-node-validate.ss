;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure recursive node validation; no admission, receipts, or Core descriptors.
(import (only-in "./functional.ss"
                 yuanxu-contract-append-map
                 yuanxu-contract-json-object?
                 yuanxu-contract-project-list
                 yuanxu-contract-member?)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node?
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node->alist
                 yuanxu-json-schema-property-name
                 yuanxu-json-schema-property-schema
                 yuanxu-json-schema-property-required?
                 yuanxu-json-schema-property->alist
                 yuanxu-json-schema-object-properties
                 yuanxu-json-schema-object-additional-properties
                 yuanxu-json-schema-object-pattern-properties
                 yuanxu-json-schema-pattern-property-schema)
        (only-in "./json-schema-values.ss" yuanxu-json-schema-null?)
        (only-in "./json-schema-validation-core.ss"
                 +yuanxu-json-schema-validation-missing+
                 yuanxu-json-schema-candidate-slot
                 yuanxu-json-schema-candidate-rows
                 yuanxu-json-schema-path-append
                 yuanxu-json-schema-schema-guided-array-values
                 yuanxu-json-schema-array-node-shape-valid?
                 yuanxu-json-schema-object-node-shape-valid?
                 yuanxu-json-schema-row-key-symbol
                 yuanxu-json-schema-row-key-string
                 yuanxu-json-schema-matching-pattern-properties)
        (only-in "./json-schema-valid.ss"
                 yuanxu-json-schema-node-valid?))
(import "./json-schema-diagnostics.ss")
(export yuanxu-json-schema-node-validate)

(def (yuanxu-json-schema-nullable-branch node)
  (and (eq? (yuanxu-json-schema-node-kind node) 'any-of)
       (let (children (yuanxu-json-schema-node-value node))
         (and (= (length children) 2)
              (cond
               ((eq? (yuanxu-json-schema-node-kind (car children)) 'null) (cadr children))
               ((eq? (yuanxu-json-schema-node-kind (cadr children)) 'null) (car children))
               (else #f))))))

(def (yuanxu-json-schema-node-validate node value path)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((yuanxu-json-schema-nullable-branch node)
      (if (yuanxu-json-schema-null? value) '()
        (yuanxu-json-schema-node-validate
          (yuanxu-json-schema-nullable-branch node) value path)))
     ((and (eq? kind 'array)
           (not (yuanxu-json-schema-array-node-shape-valid? node value)))
      (list
       (yuanxu-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive array predicate rejected the value"
        path
        value
        (yuanxu-json-schema-node->alist node))))
     ((and (eq? kind 'object)
           (not (yuanxu-json-schema-object-node-shape-valid? node value)))
      (list
       (yuanxu-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive object predicate rejected the value"
        path
        value
        (yuanxu-json-schema-node->alist node))))
     ((and (eq? kind 'one-of)
           (= (length (yuanxu-json-schema-node-value node)) 1))
      (yuanxu-json-schema-node-validate
       (car (yuanxu-json-schema-node-value node))
       value
       path))
     ((and (not (eq? kind 'array))
           (not (eq? kind 'object))
           (not (yuanxu-json-schema-node-valid? node value)))
      (list
       (yuanxu-json-schema-invalid-path-diagnostic
        'invalid-node-value
        "JSON Schema recursive node predicate rejected the value"
        path
        value
        (yuanxu-json-schema-node->alist node))))
     (else
      (cond
       ((eq? kind 'object)
        (yuanxu-json-schema-object-node-validate node value path))
       ((eq? kind 'array)
        (yuanxu-json-schema-array-node-validate node value path))
       ((and (eq? kind 'nullable)
             (not (yuanxu-json-schema-null? value)))
        (yuanxu-json-schema-node-validate
         (yuanxu-json-schema-node-value node)
         value
         path))
       (else '()))))))

(def (yuanxu-json-schema-array-node-validate node value path)
  (let ((item-node (yuanxu-json-schema-node-value node))
        (items (yuanxu-json-schema-schema-guided-array-values value)))
    (yuanxu-contract-append-map
     (lambda (indexed-item)
       (if (and (list? item-node) (>= (cdr indexed-item) (length item-node)))
         '()
         (yuanxu-json-schema-node-validate
        (if (list? item-node) (list-ref item-node (cdr indexed-item)) item-node)
        (car indexed-item)
        (yuanxu-json-schema-path-append path (cdr indexed-item)))))
     (map cons items (iota (length items))))))

(def (yuanxu-json-schema-property-validate property candidate path)
  (let* ((slot
          (yuanxu-json-schema-property-name property))
         (value
          (yuanxu-json-schema-candidate-slot candidate slot))
         (slot-path
          (yuanxu-json-schema-path-append path slot)))
    (cond
     ((eq? value +yuanxu-json-schema-validation-missing+)
      (if (yuanxu-json-schema-property-required? property)
        (list
         (yuanxu-json-schema-missing-path-diagnostic
          slot-path
          candidate
          (yuanxu-json-schema-property->alist property)))
        '()))
     (else
      (yuanxu-json-schema-node-validate
       (yuanxu-json-schema-property-schema property)
       value
       slot-path)))))

(def (yuanxu-json-schema-validation-row-value object-row)
  (let (tail (cdr object-row))
    (if (and (pair? tail)
             (null? (cdr tail))
             (not (yuanxu-contract-json-object? tail))
             (yuanxu-contract-json-object? (car tail)))
      (car tail)
      tail)))

(def (yuanxu-json-schema-pattern-row-validate pattern-property object-row path)
  (yuanxu-json-schema-node-validate
   (yuanxu-json-schema-pattern-property-schema pattern-property)
   (yuanxu-json-schema-validation-row-value object-row)
   (yuanxu-json-schema-path-append
    path
    (yuanxu-json-schema-row-key-symbol object-row))))

(def (yuanxu-json-schema-additional-property-validate additional object-row
                                                        path)
  (let ((row-path
         (yuanxu-json-schema-path-append
          path
          (yuanxu-json-schema-row-key-symbol object-row))))
    (cond
     ((eq? additional 'unspecified) '())
     ((eq? additional #t) [])
     ((eq? additional #f)
      (list
       (yuanxu-json-schema-invalid-path-diagnostic
        'additional-property-not-allowed
        "JSON Schema additionalProperties rejected object key"
        row-path
        (yuanxu-json-schema-validation-row-value object-row)
        additional)))
     ((and (yuanxu-json-schema-node? additional)
           (eq? (yuanxu-json-schema-node-kind additional) 'never))
      (list
       (yuanxu-json-schema-invalid-path-diagnostic
        'additional-property-not-allowed
        "JSON Schema additionalProperties rejected the object key"
        row-path
     (yuanxu-json-schema-validation-row-value object-row)
        (yuanxu-json-schema-node->alist additional))))
     ((yuanxu-json-schema-node? additional)
    (yuanxu-json-schema-node-validate
     additional
     (yuanxu-json-schema-validation-row-value object-row)
     row-path))
     (else '()))))

(def (yuanxu-json-schema-object-row-validate object object-row declared
                                               path)
  (let* ((row-key
          (yuanxu-json-schema-row-key-symbol object-row))
         (row-key-string
          (yuanxu-json-schema-row-key-string object-row))
         (pattern-matches
          (yuanxu-json-schema-matching-pattern-properties
           (yuanxu-json-schema-object-pattern-properties object)
           row-key-string))
         (pattern-diagnostics
          (yuanxu-contract-append-map
           (lambda (pattern-row)
             (yuanxu-json-schema-pattern-row-validate
              pattern-row
              object-row
              path))
           pattern-matches)))
    (append
     pattern-diagnostics
     (if (or (yuanxu-contract-member? row-key declared)
             (not (null? pattern-matches)))
       '()
       (yuanxu-json-schema-additional-property-validate
        (yuanxu-json-schema-object-additional-properties object)
        object-row
        path)))))

(def (yuanxu-json-schema-object-node-validate node candidate path)
  (let* ((object
          (yuanxu-json-schema-node-value node))
         (properties
          (yuanxu-json-schema-object-properties object))
         (declared
          (yuanxu-contract-project-list
           yuanxu-json-schema-property-name
           properties))
         (property-diagnostics
          (yuanxu-contract-append-map
           (lambda (property)
             (yuanxu-json-schema-property-validate
              property
              candidate
              path))
           properties))
         (map-diagnostics
          (yuanxu-contract-append-map
           (lambda (row)
             (yuanxu-json-schema-object-row-validate
              object
              row
              declared
              path))
           (yuanxu-json-schema-candidate-rows candidate))))
    (append property-diagnostics map-diagnostics)))
