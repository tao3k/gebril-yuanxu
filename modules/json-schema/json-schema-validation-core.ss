;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: shared helpers for JSON Schema value validation.
;;; Invariant: this owner has no receipt structs and no public validation API;
;;; it only normalizes candidate access, paths, shape checks, and regex rows.

(import (only-in "./json-schema-constraints.ss" yuanxu-json-schema-unique-items?)
        (only-in :clan/poo/object
                 .all-slots
                 .ref
                 .slot?
                 object?)
        (only-in "./functional.ss"
                 yuanxu-contract-any?
                 yuanxu-contract-key->string
                 yuanxu-contract-key->symbol
                 yuanxu-contract-json-object?
                 yuanxu-contract-object-ref
                 yuanxu-contract-project-list
                 yuanxu-contract-filter-map)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-pattern-property-compiled)
        (only-in :std/text/pregexp
                 pregexp
                 pregexp-match))

(export +yuanxu-json-schema-validation-missing+
        yuanxu-json-schema-candidate-slot
        yuanxu-json-schema-candidate-rows
        yuanxu-json-schema-candidate-row-slot
        yuanxu-json-schema-path->symbol
        yuanxu-json-schema-path-append
        yuanxu-json-schema-schema-guided-array?
        yuanxu-json-schema-schema-guided-array-values
        yuanxu-json-schema-schema-guided-object?
        yuanxu-json-schema-validation-node-constraints
        yuanxu-json-schema-array-constraint-valid?
        yuanxu-json-schema-object-constraint-valid?
        yuanxu-json-schema-array-node-shape-valid?
        yuanxu-json-schema-object-node-shape-valid?
        yuanxu-json-schema-object-node-rows-shape-valid?
        yuanxu-json-schema-row-key-symbol
        yuanxu-json-schema-row-key-string
        yuanxu-json-schema-pattern-property-matches?
        yuanxu-json-schema-compiled-pattern
        yuanxu-json-schema-matching-pattern-properties)

;; : JsonSchemaValidationMissing
(def +yuanxu-json-schema-validation-missing+
  (list 'yuanxu-json-schema-validation-missing))

;; : [(Pair String CompiledPattern)]
(def +yuanxu-json-schema-compiled-pattern-cache+
  '())

;; : (-> JsonSchemaCandidateObject Symbol JsonSchemaCandidateSlotValue)
(def (yuanxu-json-schema-candidate-slot candidate slot)
  (cond
   ((hash-table? candidate)
    (let* ((string-slot (and (symbol? slot) (symbol->string slot)))
           (string-value
            (if string-slot
              (hash-ref candidate
                        string-slot
                        +yuanxu-json-schema-validation-missing+)
              +yuanxu-json-schema-validation-missing+)))
      (if (eq? string-value +yuanxu-json-schema-validation-missing+)
        (hash-ref candidate slot +yuanxu-json-schema-validation-missing+)
        string-value)))
   ((yuanxu-contract-json-object? candidate)
    (yuanxu-contract-object-ref
     candidate
     slot
     +yuanxu-json-schema-validation-missing+))
   ((and (object? candidate)
         (.slot? candidate slot))
    (.ref candidate slot))
   (else +yuanxu-json-schema-validation-missing+)))

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

;; yuanxu-json-schema-candidate-row-slot
;;   : (forall (k v) (-> [(Pair k v)] k v))
;;   : (-> JsonObjectRows JsonObjectSlot JsonObjectValue)
;;   | result: matched value or +yuanxu-json-schema-validation-missing+
;;   | doc m%
;;       `yuanxu-json-schema-candidate-row-slot` returns the normalized JSON
;;       object row value for a requested slot, or the validation missing
;;       sentinel when the candidate does not provide it.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-candidate-row-slot '(("jobs" . jobs)) 'jobs)
;;       ;; => jobs
;;       ```
;;     %
;;
;; Optimization boundary: JSON Schema object keys commonly arrive as strings,
;; while generated contracts address slots as symbols.  This is intentionally a
;; single-pass normalized lookup so recursive map-value validation does not pay
;; an assq miss plus generic object-ref fallback for every row.
(def (yuanxu-json-schema-candidate-row-slot rows slot)
  (let* ((slot-symbol (yuanxu-contract-key->symbol slot))
         (slot-string (yuanxu-contract-key->string slot))
         (row
          (find
           (lambda (candidate-row)
             (let* ((key (car candidate-row))
                    (key-symbol (yuanxu-contract-key->symbol key)))
               (or (eq? key-symbol slot-symbol)
                   (and slot-string
                        (equal? (yuanxu-contract-key->string key)
                                slot-string)))))
           rows)))
    (match row
      (#f
        (yuanxu-contract-object-ref
         rows
         slot
         +yuanxu-json-schema-validation-missing+))
      ([_ . value] value))))

;; : (-> JsonSchemaPathPart String)
(def (yuanxu-json-schema-path-part->string part)
  (cond
   ((string? part) part)
   ((symbol? part) (symbol->string part))
   ((number? part) (number->string part))
   (else "value")))

;; : (-> JsonSchemaValidationPath String)
(def (yuanxu-json-schema-path->string path)
  (cond
   ((null? path) "root")
   (else
    (string-join
     (yuanxu-contract-project-list
      yuanxu-json-schema-path-part->string
      path)
     "/"))))

;; : (-> JsonSchemaValidationPath Symbol)
(def (yuanxu-json-schema-path->symbol path)
  (string->symbol
   (yuanxu-json-schema-path->string path)))

;; : (-> JsonSchemaValidationPath JsonSchemaPathPart JsonSchemaValidationPath)
(def (yuanxu-json-schema-path-append path part)
  (append path (list part)))

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

;; : (-> YuanxuJsonSchemaNode JsonSchemaCandidateSlotValue Boolean)
(def (yuanxu-json-schema-object-node-shape-valid? node value)
  (and (yuanxu-json-schema-schema-guided-object? value)
       (yuanxu-json-schema-object-node-rows-shape-valid?
        node
        (yuanxu-json-schema-candidate-rows value))))

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

;; : (-> [YuanxuJsonSchemaPatternProperty] JsonObjectKey [YuanxuJsonSchemaPatternProperty])
(def (yuanxu-json-schema-matching-pattern-properties pattern-properties key)
  (yuanxu-contract-filter-map
   (lambda (pattern-property)
     (and (yuanxu-json-schema-pattern-property-matches?
           pattern-property
           key)
          pattern-property))
   pattern-properties))
