;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: boolean fast path for normalized JSON Schema value validation.
;;; Invariant: this owner returns booleans only. Diagnostics and receipts stay
;;; in json-schema-validate.ss so the hot path avoids allocation.

(import (only-in "./json-schema-constraints.ss" yuanxu-json-schema-unique-items?)
        (only-in :clan/poo/object
                 .all-slots
                 .ref
                 object?)
        (only-in :gerbil/runtime/hash
                 list->hash-table-eq)
        (only-in "./functional.ss"
                 yuanxu-contract-all?
                 yuanxu-contract-any?
                 yuanxu-contract-member?
                 yuanxu-contract-key->string
                 yuanxu-contract-key->symbol
                 yuanxu-contract-json-object?
                 yuanxu-contract-object-ref
                 yuanxu-contract-project-list)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node?
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-property-name
                 yuanxu-json-schema-property-schema
                 yuanxu-json-schema-property-required?
                 yuanxu-json-schema-object-properties
                 yuanxu-json-schema-object-additional-properties
                 yuanxu-json-schema-object-pattern-properties
                 yuanxu-json-schema-pattern-property-compiled
                 yuanxu-json-schema-pattern-property-schema
                 yuanxu-json-schema-normalization-schema)
        (only-in "./json-schema-values.ss"
                 yuanxu-json-schema-null?)
        (only-in :std/text/pregexp
                 pregexp
                 pregexp-match))

(export yuanxu-json-schema-node-valid?)

;; : JsonSchemaValidationMissing
(def +yuanxu-json-schema-validation-missing+
  (list 'yuanxu-json-schema-validation-missing))

;; : [(Pair String CompiledPattern)]
(def +yuanxu-json-schema-compiled-pattern-cache+
  '())

;; : HashTable
(def +yuanxu-json-schema-property-index-cache+
  (make-hash-table-eq))

;; : (-> JsonSchemaCandidateObject JsonSchemaCandidateRows)
(def (yuanxu-json-schema-candidate-rows candidate)
  (cond
   ((hash-table? candidate) (hash->list candidate))
   ((yuanxu-contract-json-object? candidate)
    candidate)
   ((object? candidate)
    (yuanxu-contract-project-list
     (lambda (slot)
       (cons slot (.ref candidate slot)))
     (.all-slots candidate)))
   (else '())))

;; : (-> JsonSchemaCandidateRows Symbol JsonSchemaCandidateSlotValue)
(def (yuanxu-json-schema-row-value row)
  (let (tail (cdr row))
    (if (and (pair? tail)
             (null? (cdr tail))
             (not (yuanxu-contract-json-object? tail))
             (yuanxu-contract-json-object? (car tail)))
      (car tail)
      tail)))

;; Normalize a candidate object once per recursive object validation. Reversing
;; the rows before the native constructor preserves leftmost JSON-key binding.
;; : (-> JsonSchemaCandidateRows HashTable)
(def (yuanxu-json-schema-candidate-row-index rows)
  (list->hash-table-eq
   (reverse
    (map (lambda (row)
           (cons (yuanxu-contract-key->symbol (car row))
                 (yuanxu-json-schema-row-value row)))
         rows))))

;; : (-> HashTable Symbol JsonSchemaCandidateSlotValue)
(def (yuanxu-json-schema-candidate-index-slot index slot)
  (let* ((string-slot (and (symbol? slot) (symbol->string slot)))
         (string-value
          (if string-slot
            (hash-ref index
                      string-slot
                      +yuanxu-json-schema-validation-missing+)
            +yuanxu-json-schema-validation-missing+)))
    (if (eq? string-value +yuanxu-json-schema-validation-missing+)
      (hash-ref index slot +yuanxu-json-schema-validation-missing+)
      string-value)))

;; : (-> JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-schema-guided-array? value)
  (or (list? value)
      (vector? value)))

;; : (-> JsonSchemaCandidateSlotValue [JsonSchemaCandidateSlotValue])
(def (yuanxu-json-schema-schema-guided-array-values value)
  (cond
   ((vector? value) (vector->list value))
   ((list? value) value)
   (else '())))

;; : (-> JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-schema-guided-object? value)
  (or (hash-table? value)
      (yuanxu-contract-json-object? value)
      (object? value)))

;; : (-> YuanxuJsonSchemaNode Alist)
(def (yuanxu-json-schema-validation-node-constraints node)
  (yuanxu-contract-object-ref
   (yuanxu-json-schema-node-metadata node)
   'constraints
   '()))

;; : (-> JsonSchemaConstraint Integer Boolean)
(def (yuanxu-json-schema-object-constraint-valid? constraint size)
  (let ((key (car constraint))
        (bound (cdr constraint)))
    (cond
     ((eq? key 'minProperties) (>= size bound))
     ((eq? key 'maxProperties) (<= size bound))
     (else #t))))

;; : (-> JsonSchemaConstraint Integer Boolean)
(def (yuanxu-json-schema-array-constraint-valid? constraint size)
  (let ((key (car constraint))
        (bound (cdr constraint)))
    (cond
     ((eq? key 'minItems) (>= size bound))
     ((eq? key 'maxItems) (<= size bound))
     (else #t))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-array-node-shape-valid? node value)
  (and (yuanxu-json-schema-schema-guided-array? value)
       (or (not (yuanxu-contract-object-ref
                 (yuanxu-json-schema-validation-node-constraints node)
                 'uniqueItems #f))
           (yuanxu-json-schema-unique-items? value))
       (let (constraints
             (yuanxu-json-schema-validation-node-constraints node))
         (if (null? constraints)
           #t
           (let (size
                 (length
                  (yuanxu-json-schema-schema-guided-array-values value)))
             (not
              (yuanxu-contract-any?
               (lambda (constraint)
                 (not
                  (yuanxu-json-schema-array-constraint-valid?
                   constraint
                   size)))
               constraints)))))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateRows Boolean)
(def (yuanxu-json-schema-object-node-rows-shape-valid? node rows)
  (let (constraints
        (yuanxu-json-schema-validation-node-constraints node))
    (if (null? constraints)
      #t
      (let (size (length rows))
        (not
         (yuanxu-contract-any?
          (lambda (constraint)
            (not
             (yuanxu-json-schema-object-constraint-valid?
              constraint
              size)))
          constraints))))))

;; : (-> JsonSchemaObjectRow Symbol)
(def (yuanxu-json-schema-row-key-symbol row)
  (yuanxu-contract-key->symbol (car row)))

;; : (-> JsonSchemaObjectRow String)
(def (yuanxu-json-schema-row-key-string row)
  (or (yuanxu-contract-key->string (car row))
      (symbol->string (yuanxu-json-schema-row-key-symbol row))))

;; : (-> YuanxuJsonSchemaPatternProperty JsonObjectKey Boolean)
(def (yuanxu-json-schema-pattern-property-matches? pattern-property key)
  (let (compiled-pattern
       (or (yuanxu-json-schema-pattern-property-compiled pattern-property)
           #f))
    (and compiled-pattern
         (if (pregexp-match compiled-pattern key) #t #f))))

;; : (-> RegexSource CompiledPattern)
(def (yuanxu-json-schema-compiled-pattern pattern)
  (let (entry (assoc pattern +yuanxu-json-schema-compiled-pattern-cache+))
    (if entry
      (cdr entry)
      (let (compiled-pattern
            (with-catch
             (lambda (_failure) #f)
             (lambda ()
               (pregexp pattern))))
        (when compiled-pattern
          (set! +yuanxu-json-schema-compiled-pattern-cache+
                (cons (cons pattern compiled-pattern)
                      +yuanxu-json-schema-compiled-pattern-cache+)))
        compiled-pattern))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-node-valid? node value)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((eq? kind 'array)
      (yuanxu-json-schema-array-node-valid? node value))
     ((eq? kind 'object)
      (yuanxu-json-schema-object-node-valid? node value))
     ((and (eq? kind 'nullable)
           (not (yuanxu-json-schema-null? value)))
      (yuanxu-json-schema-node-valid?
       (yuanxu-json-schema-node-value node)
       value))
     (else
      (yuanxu-json-schema-node-shallow-valid? node value)))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-node-shallow-valid? node value)
  (and (yuanxu-json-schema-node-kind-valid? node value)
       (yuanxu-json-schema-node-constraints-valid? node value)))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-node-kind-valid? node value)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((eq? kind 'boolean-schema) (yuanxu-json-schema-node-value node))
     ((eq? kind 'always) #t)
     ((eq? kind 'never) #f)
     ((eq? kind 'string) (string? value))
     ((eq? kind 'number) (number? value))
     ((eq? kind 'integer) (integer? value))
     ((eq? kind 'boolean) (boolean? value))
     ((eq? kind 'null) (yuanxu-json-schema-null? value))
     ((eq? kind 'const)
      (equal? value (yuanxu-json-schema-node-value node)))
     ((eq? kind 'enum)
      (yuanxu-contract-member?
       value
       (yuanxu-json-schema-node-value node)))
     ((eq? kind 'any-of)
      (yuanxu-contract-any?
       (lambda (child)
         (yuanxu-json-schema-node-valid? child value))
       (yuanxu-json-schema-node-value node)))
     ((eq? kind 'all-of)
      (yuanxu-contract-all?
       (lambda (child)
         (yuanxu-json-schema-node-valid? child value))
       (yuanxu-json-schema-node-value node)))
     ((eq? kind 'one-of)
      (= (fold
          (lambda (child count)
            (if (yuanxu-json-schema-node-valid? child value)
              (+ count 1)
              count))
          0
          (yuanxu-json-schema-node-value node))
         1))
     (else #t))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-node-constraints-valid? node value)
  (not
   (yuanxu-contract-any?
    (lambda (constraint)
      (not
       (yuanxu-json-schema-node-constraint-valid?
        constraint
        value)))
    (yuanxu-json-schema-validation-node-constraints node))))

;; : (-> JsonSchemaConstraint JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-node-constraint-valid? constraint value)
  (let ((key (car constraint))
        (bound (cdr constraint)))
    (cond
     ((eq? key 'minLength)
      (yuanxu-json-schema-min-length-valid? bound value))
     ((eq? key 'maxLength)
      (yuanxu-json-schema-max-length-valid? bound value))
     ((eq? key 'minimum)
      (yuanxu-json-schema-minimum-valid? bound value))
     ((eq? key 'maximum)
      (yuanxu-json-schema-maximum-valid? bound value))
     ((eq? key 'exclusiveMinimum)
      (yuanxu-json-schema-exclusive-minimum-valid? bound value))
     ((eq? key 'exclusiveMaximum)
      (yuanxu-json-schema-exclusive-maximum-valid? bound value))
     ((or (eq? key 'minItems)
          (eq? key 'maxItems))
      (yuanxu-json-schema-array-value-constraint-valid? constraint value))
     ((or (eq? key 'minProperties)
          (eq? key 'maxProperties))
      (yuanxu-json-schema-object-value-constraint-valid? constraint value))
     ((eq? key 'pattern)
      (yuanxu-json-schema-pattern-constraint-valid? bound value))
     (else #t))))

;; : (-> Integer JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-min-length-valid? bound value)
  (or (not (string? value))
      (>= (string-length value) bound)))

;; : (-> Integer JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-max-length-valid? bound value)
  (or (not (string? value))
      (<= (string-length value) bound)))

;; : (-> Number JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-minimum-valid? bound value)
  (or (not (number? value))
      (>= value bound)))

;; : (-> Number JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-maximum-valid? bound value)
  (or (not (number? value))
      (<= value bound)))

;; : (-> Number JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-exclusive-minimum-valid? bound value)
  (or (not (number? value))
      (> value bound)))

;; : (-> Number JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-exclusive-maximum-valid? bound value)
  (or (not (number? value))
      (< value bound)))

;; : (-> JsonSchemaConstraint JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-array-value-constraint-valid? constraint value)
  (or (not (yuanxu-json-schema-schema-guided-array? value))
      (yuanxu-json-schema-array-constraint-valid?
       constraint
       (length (yuanxu-json-schema-schema-guided-array-values value)))))

;; : (-> JsonSchemaConstraint JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-object-value-constraint-valid? constraint value)
  (or (not (yuanxu-json-schema-schema-guided-object? value))
      (yuanxu-json-schema-object-constraint-valid?
       constraint
       (length (yuanxu-json-schema-candidate-rows value)))))

;; : (-> RegexSource JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-pattern-constraint-valid? bound value)
  (or (not (string? value))
      (let (compiled-pattern
            (yuanxu-json-schema-compiled-pattern bound))
        (and compiled-pattern
             (if (pregexp-match compiled-pattern value) #t #f)))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaArrayCandidate Boolean)
(def (yuanxu-json-schema-array-node-valid? node value)
  (and (yuanxu-json-schema-array-node-shape-valid? node value)
       (let ((item-node (yuanxu-json-schema-node-value node))
             (items (yuanxu-json-schema-schema-guided-array-values value)))
         (if (list? item-node)
           (let loop ((nodes item-node) (values items))
             (or (null? nodes) (null? values)
                 (and (yuanxu-json-schema-node-valid? (car nodes) (car values))
                      (loop (cdr nodes) (cdr values)))))
           (yuanxu-contract-all?
            (lambda (item) (yuanxu-json-schema-node-valid? item-node item))
            items)))))

;; : (-> YuanxuJsonSchemaProperty HashTable Boolean)
(def (yuanxu-json-schema-property-valid/index? property candidate-index)
  (let (value
        (yuanxu-json-schema-candidate-index-slot
         candidate-index
         (yuanxu-json-schema-property-name property)))
    (if (eq? value +yuanxu-json-schema-validation-missing+)
      (not (yuanxu-json-schema-property-required? property))
      (yuanxu-json-schema-node-valid?
       (yuanxu-json-schema-property-schema property)
       value))))

;; : (-> YuanxuJsonSchemaPatternProperty JsonSchemaObjectRow Boolean)
(def (yuanxu-json-schema-pattern-row-valid? pattern-property object-row)
  (yuanxu-json-schema-node-valid?
   (yuanxu-json-schema-pattern-property-schema pattern-property)
   (yuanxu-json-schema-row-value object-row)))

;; : (-> JsonSchemaMapValueSchema JsonSchemaObjectRow Boolean)
(def (yuanxu-json-schema-additional-property-valid? additional object-row)
  (cond
   ((eq? additional 'unspecified) #t)
   ((boolean? additional) additional)
   ((and (yuanxu-json-schema-node? additional)
         (eq? (yuanxu-json-schema-node-kind additional) 'never))
    #f)
   ((yuanxu-json-schema-node? additional)
    (yuanxu-json-schema-node-valid?
     additional
     (yuanxu-json-schema-row-value object-row)))
     (else #f)))

;; : (-> YuanxuJsonSchemaObject JsonSchemaObjectRow [Symbol] Boolean)
(def (yuanxu-json-schema-object-row-valid? object object-row declared-index)
  (let* ((row-key
          (yuanxu-json-schema-row-key-symbol object-row))
         (declared? (hash-key? declared-index row-key))
         (pattern-properties
          (yuanxu-json-schema-object-pattern-properties object)))
    (if (null? pattern-properties)
      (or declared?
          (yuanxu-json-schema-additional-property-valid?
           (yuanxu-json-schema-object-additional-properties object)
           object-row))
      (let (pattern-state
            (yuanxu-json-schema-pattern-row-state
             pattern-properties
             (yuanxu-json-schema-row-key-string object-row)
             object-row))
        (and
         (not (eq? pattern-state 'invalid))
         (or declared?
             (eq? pattern-state 'matched)
             (yuanxu-json-schema-additional-property-valid?
              (yuanxu-json-schema-object-additional-properties object)
              object-row)))))))

;; : (-> [YuanxuJsonSchemaPatternProperty] JsonObjectKey JsonSchemaObjectRow Symbol)
(def (yuanxu-json-schema-pattern-row-state pattern-properties key object-row)
  (fold
   (lambda (pattern-property state)
     (cond
      ((eq? state 'invalid) 'invalid)
      ((yuanxu-json-schema-pattern-property-matches?
        pattern-property
        key)
       (if (yuanxu-json-schema-pattern-row-valid?
            pattern-property
            object-row)
         'matched
         'invalid))
      (else state)))
   'unmatched
   pattern-properties))

;; : (-> YuanxuJsonSchemaObject HashTable)
(def (yuanxu-json-schema-object-property-index object)
  (or (hash-get +yuanxu-json-schema-property-index-cache+ object)
      (let (index (make-hash-table))
        (for-each
         (lambda (property)
           (hash-put! index
                      (yuanxu-json-schema-property-name property)
                      #t))
         (yuanxu-json-schema-object-properties object))
        (hash-put! +yuanxu-json-schema-property-index-cache+ object index)
        index)))

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateObject Boolean)
(def (yuanxu-json-schema-object-node-valid? node candidate)
  (and (yuanxu-json-schema-schema-guided-object? candidate)
       (let* ((object
               (yuanxu-json-schema-node-value node))
              (properties
               (yuanxu-json-schema-object-properties object))
              (pattern-properties
               (yuanxu-json-schema-object-pattern-properties object))
              (additional-properties
               (yuanxu-json-schema-object-additional-properties object))
              (constraints
               (yuanxu-json-schema-validation-node-constraints node))
              ;; A permissive object with no pattern or size constraints is
              ;; completely checked by its declared property lookups.  Keep a
              ;; native std/text/json hash native instead of allocating
              ;; hash->list rows that no rule consumes.
              (rows-required?
               (or (pair? constraints)
                   (pair? pattern-properties)
                   (not (eq? additional-properties 'unspecified))))
              (rows
               (if rows-required?
                 (yuanxu-json-schema-candidate-rows candidate)
                 '()))
              (candidate-index
               (and (pair? properties)
                    (if (hash-table? candidate)
                      candidate
                      (yuanxu-json-schema-candidate-row-index rows))))
              (declared-index
               (yuanxu-json-schema-object-property-index object)))
         (and
          (or (not (pair? constraints))
              (yuanxu-json-schema-object-node-rows-shape-valid? node rows))
          (yuanxu-contract-all?
           (lambda (property)
             (yuanxu-json-schema-property-valid/index?
              property
              candidate-index))
           properties)
          (or (not rows-required?)
              (yuanxu-contract-all?
               (lambda (row)
                 (yuanxu-json-schema-object-row-valid?
                  object
                  row
                  declared-index))
               rows))))))
