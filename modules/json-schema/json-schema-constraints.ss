;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: JSON Schema validation keyword constraints.
;;; Invariant: this owner stores small constraint metadata and compiles it into
;;; predicates; it does not parse full schemas or emit object contracts.

(import (only-in :clan/poo/object object? .all-slots .ref)
        (only-in "./functional.ss"
                 yuanxu-contract-all?
                 yuanxu-contract-key->string
                 yuanxu-contract-json-object?
                 yuanxu-contract-object-ref
                 yuanxu-contract-project-list
                 yuanxu-contract-map-pair-with-diagnostics)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-node-record
                 yuanxu-json-schema-diagnostic-record)
        (only-in :std/text/pregexp
                 pregexp
                 pregexp-match))

(export +yuanxu-json-schema-constraint-keywords+
        yuanxu-json-schema-parse-result-with-constraints
        yuanxu-json-schema-apply-node-constraints
        yuanxu-json-schema-unique-items?)

;; +yuanxu-json-schema-constraint-keywords+
;;   : [Symbol]
;;   | doc m%
;;       Supported validation keywords carried as normalized node metadata.
;;     %
(def +yuanxu-json-schema-constraint-keywords+
  '(minLength
    maxLength
    minimum
    maximum
    exclusiveMinimum
    exclusiveMaximum
    minItems
    maxItems
    uniqueItems
    minProperties
    maxProperties
    pattern))

;; yuanxu-json-schema-non-negative-integer?
;;   : (-> JsonSchemaDatum Boolean)
;;   | doc m%
;;       Recognize JSON Schema length/count bounds.
;;     %
(def (yuanxu-json-schema-non-negative-integer? value)
  (and (integer? value)
       (>= value 0)))

;; yuanxu-json-schema-valid-constraint-value?
;;   : (-> Symbol JsonSchemaDatum Boolean)
;;   | doc m%
;;       Validate the small P0 constraint value shapes before adding them to IR.
;;     %
(def (yuanxu-json-schema-valid-constraint-value? key value)
  (cond
   ((or (eq? key 'minLength)
        (eq? key 'maxLength)
        (eq? key 'minItems)
        (eq? key 'maxItems)
        (eq? key 'minProperties)
        (eq? key 'maxProperties))
    (yuanxu-json-schema-non-negative-integer? value))
   ((or (eq? key 'minimum)
        (eq? key 'maximum)
        (eq? key 'exclusiveMinimum)
        (eq? key 'exclusiveMaximum))
    (number? value))
   ((eq? key 'uniqueItems) (boolean? value))
   ((eq? key 'pattern)
    (and (string? value)
         (with-catch
          (lambda (_failure) #f)
          (lambda ()
            (pregexp value)
            #t))))
   (else #f)))

;; yuanxu-json-schema-constraint-diagnostic
;;   : (-> Symbol JsonSchemaDatum Symbol YuanxuJsonSchemaDiagnostic)
;;   | doc m%
;;       Emit a warning when a supported constraint key has an invalid value
;;       shape. The bridge keeps generation alive with a safe fallback.
;;     %
(def (yuanxu-json-schema-constraint-diagnostic key value context)
  (yuanxu-json-schema-diagnostic-record
   'warning
   'invalid-constraint-value
   "JSON Schema constraint has an invalid value shape"
   value
   `((context . ,context)
     (keyword . ,key)
     (owner . json-schema-constraints))))

;; yuanxu-json-schema-parse-constraint
;;   : (-> JsonSchemaObjectRows Symbol Symbol JsonSchemaMissingSentinel Pair)
;;   | result: maybe constraint row paired with diagnostics
;;   | doc m%
;;       Parse one optional constraint keyword from a schema object.
;;     %
(def (yuanxu-json-schema-parse-constraint schema key context missing)
  (let (value
        (yuanxu-contract-object-ref schema key missing))
    (cond
     ((eq? value missing)
      (cons #f '()))
     ((yuanxu-json-schema-valid-constraint-value? key value)
      (cons (cons key value) '()))
     (else
      (cons
       #f
       (list
        (yuanxu-json-schema-constraint-diagnostic
         key
         value
         context)))))))

;; yuanxu-json-schema-parse-constraints
;;   : (-> JsonSchemaObjectRows Symbol JsonSchemaMissingSentinel Pair)
;;   | result: constraint alist paired with diagnostics
;;   | doc m%
;;       Collect supported validation keywords into bounded metadata rows.
;;     %
(def (yuanxu-json-schema-parse-constraints schema context missing)
  (let* ((parsed
          (yuanxu-contract-map-pair-with-diagnostics
           (lambda (key)
             (yuanxu-json-schema-parse-constraint
              schema
              key
              context
              missing))
           +yuanxu-json-schema-constraint-keywords+
           '()))
         (constraints
          (filter-map
           (lambda (constraint)
             constraint)
           (car parsed))))
    (cons constraints (cdr parsed))))

;; yuanxu-json-schema-node-with-constraints
;;   : (-> YuanxuJsonSchemaNode Alist YuanxuJsonSchemaNode)
;;   | doc m%
;;       Attach parsed constraints to node metadata without changing the node
;;       family. The emitter owns executable predicate composition.
;;     %
(def (yuanxu-json-schema-node-with-constraints node constraints)
  (if (null? constraints)
    node
    (yuanxu-json-schema-node-record
     (yuanxu-json-schema-node-kind node)
     (yuanxu-json-schema-node-value node)
     (append
      (yuanxu-json-schema-node-metadata node)
      (list (cons 'constraints constraints))))))

;; yuanxu-json-schema-parse-result-with-constraints
;;   : (-> JsonSchemaObjectRows Symbol JsonSchemaMissingSentinel JsonSchemaParseResult JsonSchemaParseResult)
;;   | doc m%
;;       Merge validation-keyword metadata into an already parsed schema node.
;;     %
(def (yuanxu-json-schema-parse-result-with-constraints schema context missing
                                                         parsed)
  (let (constraints
        (yuanxu-json-schema-parse-constraints schema context missing))
    (cons
     (yuanxu-json-schema-node-with-constraints
      (car parsed)
      (car constraints))
     (append (cdr parsed) (cdr constraints)))))

;; yuanxu-json-schema-node-constraints
;;   : (-> YuanxuJsonSchemaNode Alist)
;;   | doc m%
;;       Read normalized constraint metadata from one schema node.
;;     %
(def (yuanxu-json-schema-node-constraints node)
  (yuanxu-contract-object-ref
   (yuanxu-json-schema-node-metadata node)
   'constraints
   '()))

;; JSON equality is recursive, numeric, and insensitive to object key order.
;; Empty objects should use a POO object/hash and empty arrays a vector at
;; ambiguous wire boundaries. Never use Scheme equal? as provider set identity.
(def (yuanxu-json-schema-equality-rows value)
  (cond ((hash-table? value) (hash->list value))
        ((object? value) (map (lambda (key) (cons key (.ref value key)))
                               (.all-slots value)))
        ((and (pair? value) (yuanxu-contract-json-object? value)) value)
        (else #f)))

(def (yuanxu-json-schema-value=? left right)
  (let ((a (yuanxu-json-schema-equality-rows left))
        (b (yuanxu-json-schema-equality-rows right)))
    (cond
     ((and a b)
      (and (= (length a) (length b))
           (every (lambda (entry)
                    (let (other (find (lambda (row)
                                        (equal? (yuanxu-contract-key->string (car row))
                                                (yuanxu-contract-key->string (car entry)))) b))
                      (and other (yuanxu-json-schema-value=? (cdr entry) (cdr other))))) a)))
     ((or a b) #f)
     ((and (number? left) (number? right)) (= left right))
     ((and (or (list? left) (vector? left)) (or (list? right) (vector? right)))
      (let ((xs (if (vector? left) (vector->list left) left))
            (ys (if (vector? right) (vector->list right) right)))
        (and (= (length xs) (length ys))
             (every identity (map yuanxu-json-schema-value=? xs ys)))))
     (else (equal? left right)))))

(def (yuanxu-json-schema-unique-items? values)
  (let loop ((rest (if (vector? values) (vector->list values) values)))
    (or (null? rest)
        (and (not (find (lambda (other)
                         (yuanxu-json-schema-value=? (car rest) other)) (cdr rest)))
             (loop (cdr rest))))))

;; yuanxu-json-schema-constraint-predicate
;;   : (-> Procedure Pair JsonSchemaPredicate)
;;   | doc m%
;;       Compile one normalized validation keyword into a predicate. JSON Schema
;;       type-specific constraints pass non-applicable values.
;;     %
(def (yuanxu-json-schema-constraint-predicate array-value? constraint)
  (let ((key (car constraint))
        (bound (cdr constraint)))
    (cond
     ((eq? key 'minLength)
      (lambda (value)
        (or (not (string? value))
            (>= (string-length value) bound))))
     ((eq? key 'maxLength)
      (lambda (value)
        (or (not (string? value))
            (<= (string-length value) bound))))
     ((eq? key 'minimum)
      (lambda (value)
        (or (not (number? value))
            (>= value bound))))
     ((eq? key 'maximum)
      (lambda (value)
        (or (not (number? value))
            (<= value bound))))
     ((eq? key 'exclusiveMinimum)
      (lambda (value)
        (or (not (number? value))
            (> value bound))))
     ((eq? key 'exclusiveMaximum)
      (lambda (value)
        (or (not (number? value))
            (< value bound))))
     ((eq? key 'uniqueItems)
      (lambda (value)
        (or (not bound) (not (array-value? value))
            (yuanxu-json-schema-unique-items? value))))
     ((eq? key 'minItems)
      (lambda (value)
        (or (not (array-value? value))
            (>= (length (if (vector? value) (vector->list value) value)) bound))))
     ((eq? key 'maxItems)
      (lambda (value)
        (or (not (array-value? value))
            (<= (length (if (vector? value) (vector->list value) value)) bound))))
     ((eq? key 'minProperties)
      (lambda (value)
        (or (not (yuanxu-contract-json-object? value))
            (>= (length value) bound))))
     ((eq? key 'maxProperties)
      (lambda (value)
        (or (not (yuanxu-contract-json-object? value))
            (<= (length value) bound))))
     ((eq? key 'pattern)
      (let (compiled-pattern (pregexp bound))
        (lambda (value)
          (or (not (string? value))
              (if (pregexp-match compiled-pattern value) #t #f)))))
     (else
      (lambda (_value) #t)))))

;; yuanxu-json-schema-constraints-predicate
;;   : (-> Procedure Alist JsonSchemaPredicate)
;;   | doc m%
;;       Combine normalized constraints into one predicate closure.
;;     %
(def (yuanxu-json-schema-constraints-predicate array-value? constraints)
  (let (predicates
         (yuanxu-contract-project-list
          (lambda (constraint)
            (yuanxu-json-schema-constraint-predicate array-value? constraint))
          constraints))
    (lambda (value)
      (yuanxu-contract-all? (lambda (predicate) (predicate value)) predicates))))

;; yuanxu-json-schema-apply-node-constraints
;;   : (-> YuanxuJsonSchemaNode JsonSchemaPredicate Procedure JsonSchemaPredicate)
;;   | doc m%
;;       Add metadata-owned constraints to a node's base predicate once during
;;       contract emission.
;;     %
(def (yuanxu-json-schema-apply-node-constraints node base-predicate
                                                  array-value?)
  (let (constraints
        (yuanxu-json-schema-node-constraints node))
    (if (null? constraints)
      base-predicate
      (let (additional (yuanxu-json-schema-constraints-predicate array-value? constraints))
        (lambda (value) (and (base-predicate value) (additional value)))))))
