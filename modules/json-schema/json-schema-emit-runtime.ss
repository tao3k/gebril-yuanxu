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
                 yuanxu-json-schema-pattern-property-schema
                 yuanxu-json-schema-pattern-property-pattern
                 yuanxu-json-schema-pattern-property->alist))


(import (only-in "./json-schema-values.ss" yuanxu-json-schema-null?))
(export #t yuanxu-json-schema-null?)

;; yuanxu-json-schema-any?
;;   : (-> JsonSchemaDatum Boolean)
;;   | doc m%
;;       Accept any value for fallback schemas that are still proof-visible
;;       through metadata and diagnostics.
;;     %
(def (yuanxu-json-schema-any? _value)
  #t)


;; yuanxu-json-schema-json-object-value?
;;   : (-> JsonSchemaDatum Boolean)
;;   | doc m%
;;       Delegate object recognition to the contract functional boundary.
;;     %
(def (yuanxu-json-schema-json-object-value? value)
  (yuanxu-contract-json-object? value))

;; yuanxu-json-schema-json-array-value?
;;   : (-> JsonSchemaDatum Boolean)
;;   | doc m%
;;       Array schemas determine list/vector interpretation, including arrays
;;       of records. Wire producers use vectors/hashes to avoid ambiguity.
;;     %
(def (yuanxu-json-schema-json-array-value? value)
  (or (vector? value) (list? value)))

;; yuanxu-json-schema-integer-value?
;;   : (-> JsonSchemaDatum Boolean)
;;   | doc m%
;;       Keep integer predicate naming stable for generated contract metadata.
;;     %
(def (yuanxu-json-schema-integer-value? value)
  (integer? value))

;; yuanxu-json-schema-symbol-string
;;   : (-> JsonSchemaKey String)
;;   | doc m%
;;       Convert object keys and slots to stable path fragments.
;;     %
(def (yuanxu-json-schema-symbol-string value)
  (or (yuanxu-contract-key->string value)
      "json-schema"))

;; yuanxu-json-schema-contract-key
;;   : (-> Symbol Symbol Symbol)
;;   | doc m%
;;       Build the generated slot contract key from object and slot identity.
;;     %
(def (yuanxu-json-schema-contract-key object-key slot)
  (string->symbol
   (string-append
    (yuanxu-json-schema-symbol-string object-key)
    "/"
    (yuanxu-json-schema-symbol-string slot))))

;; yuanxu-json-schema-const-predicate
;;   : (-> JsonSchemaDatum JsonSchemaPredicate)
;;   | doc m%
;;       Build a reusable equality predicate for `const` schemas.
;;     %
(def (yuanxu-json-schema-const-predicate expected)
  (lambda (value)
    (equal? value expected)))

;; yuanxu-json-schema-enum-predicate
;;   : (-> [JsonSchemaDatum] JsonSchemaPredicate)
;;   | doc m%
;;       Build a reusable membership predicate for `enum` schemas.
;;     %
(def (yuanxu-json-schema-enum-predicate values)
  (lambda (value)
    (yuanxu-contract-member? value values)))

;; yuanxu-json-schema-nullable-predicate
;;   : (-> JsonSchemaPredicate JsonSchemaPredicate)
;;   | doc m%
;;       Build a nullable predicate without re-reading the normalized node.
;;     %
(def (yuanxu-json-schema-nullable-predicate predicate)
  (lambda (value)
    (or (yuanxu-json-schema-null? value)
        (predicate value))))

;; yuanxu-json-schema-array-predicate
;;   : (-> JsonSchemaPredicate JsonSchemaPredicate)
;;   | doc m%
;;       Build a homogeneous array predicate from the already-emitted item
;;       predicate. Runtime checks stay bounded to one list scan and do not
;;       interpret the normalized schema again.
;;     %
(def (yuanxu-json-schema-array-predicate item-predicate . maybe-metadata)
  (let* ((metadata (if (null? maybe-metadata) '() (car maybe-metadata)))
         (min-items (yuanxu-json-schema-metadata-ref metadata 'min-items #f))
         (max-items (yuanxu-json-schema-metadata-ref metadata 'max-items #f)))
    (lambda (value)
      (and (yuanxu-json-schema-json-array-value? value)
           (let (items (if (vector? value) (vector->list value) value))
             (and (or (not min-items) (>= (length items) min-items))
                  (or (not max-items) (<= (length items) max-items))
                  (yuanxu-contract-all? item-predicate items)))))))

;; : (-> JsonSchemaMetadata Symbol JsonSchemaDatum JsonSchemaDatum)
(def (yuanxu-json-schema-metadata-ref metadata key default)
  (let ((found (assoc key metadata)))
    (if found (cdr found) default)))

;; yuanxu-json-schema-schema-ref
;;   : (-> JsonSchemaSource JsonSchemaKey JsonSchemaDatum JsonSchemaDatum)
;;   | doc m%
;;       Read one normalized schema entry by string-or-symbol key and return the
;;       caller supplied default when the entry is absent.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-schema-ref '((type . "object")) "type" #f)
;;       ;; => "object"
;;       ```
;;     %
;; Boundary: schema emission stays pure; specialized JSON Schema branches
;; use functional combinators instead of runtime mutation or ad hoc walkers.
(def (yuanxu-json-schema-schema-ref schema key default)
  (let ((found (and (list? schema)
                    (find
                     (lambda (entry)
                       (and (pair? entry)
                            (yuanxu-json-schema-schema-key=?
                             (car entry)
                             key)))
                     schema))))
    (if found
      (let ((value (cdr found)))
        (if (and (pair? value) (null? (cdr value)))
          (car value)
          value))
      default)))

;; : (-> JsonSchemaKey JsonSchemaKey Boolean)
(def (yuanxu-json-schema-schema-key=? left right)
  (cond
   ((equal? left right) #t)
   ((and (symbol? left) (string? right))
    (string=? (symbol->string left) right))
   ((and (string? left) (symbol? right))
    (string=? left (symbol->string right)))
   (else #f)))

;; : (-> JsonSchemaKey JsonSchemaKey)
(def (yuanxu-json-schema-schema-key->string key)
  (cond
   ((string? key) key)
   ((symbol? key) (symbol->string key))
   (else key)))

;; : (-> YuanxuJsonSchemaNode JsonSchemaPredicate)
(def (yuanxu-json-schema-string-predicate node)
  (let ((schema (yuanxu-json-schema-node-value node)))
    (lambda (value)
      (and (string? value)
           (let ((min-length
                  (yuanxu-json-schema-schema-ref schema "minLength" #f))
                 (max-length
                  (yuanxu-json-schema-schema-ref schema "maxLength" #f))
                 (pattern
                  (yuanxu-json-schema-schema-ref schema "pattern" #f)))
             (and (or (not min-length) (>= (string-length value) min-length))
                  (or (not max-length) (<= (string-length value) max-length))
                  (or (not pattern)
                      (yuanxu-json-schema-pattern-runtime-match?
                       pattern
                       value))))))))

;; : (-> JsonSchemaPattern String Boolean)
(def (yuanxu-json-schema-pattern-runtime-match? pattern value)
  (with-catch
   (lambda (_error) #f)
   (lambda ()
     (if (string? pattern)
       (if (pregexp-match (pregexp pattern) value) #t #f)
       #f))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaPredicate JsonSchemaPredicate)
(def (yuanxu-json-schema-number-predicate node base-predicate)
  (let ((schema (yuanxu-json-schema-node-value node)))
    (lambda (value)
      (and (base-predicate value)
           (let ((minimum (yuanxu-json-schema-schema-ref schema "minimum" #f))
                 (maximum (yuanxu-json-schema-schema-ref schema "maximum" #f))
                 (exclusive-minimum
                  (yuanxu-json-schema-schema-ref schema "exclusiveMinimum" #f))
                 (exclusive-maximum
                  (yuanxu-json-schema-schema-ref schema "exclusiveMaximum" #f)))
             (and (or (not minimum) (>= value minimum))
                  (or (not maximum) (<= value maximum))
                  (or (not exclusive-minimum) (> value exclusive-minimum))
                  (or (not exclusive-maximum) (< value exclusive-maximum))))))))

;; : (-> YuanxuJsonSchemaNode JsonSchemaPredicate)
(def (yuanxu-json-schema-object-predicate node)
  (let ((schema (yuanxu-json-schema-node-value node))
        (metadata (yuanxu-json-schema-node-metadata node)))
    (lambda (value)
      (let* ((raw-rows (yuanxu-json-schema-object-runtime-rows value))
             (rows
              (yuanxu-json-schema-object-runtime-rows-for-schema
               schema
               raw-rows)))
        (and rows
             (yuanxu-json-schema-json-object-value? rows)
             (let ((min-properties
                    (yuanxu-json-schema-metadata-ref
                     metadata
                     'min-properties
                     #f))
                   (max-properties
                    (yuanxu-json-schema-metadata-ref
                     metadata
                     'max-properties
                     #f)))
               (and (or (not min-properties) (>= (length rows) min-properties))
                    (or (not max-properties) (<= (length rows) max-properties))))
             (yuanxu-json-schema-object-children-valid? schema rows))))))

;; : (-> JsonSchemaDatum JsonSchemaRuntimeObjectRows)
(def (yuanxu-json-schema-object-runtime-rows value)
  (cond
   ((list? value) value)
   (else
    (with-catch
     (lambda (_error) #f)
     (lambda () (.alist value))))))

;; : (-> JsonSchemaSource JsonSchemaRuntimeObjectRows JsonSchemaRuntimeObjectRows)
(def (yuanxu-json-schema-object-runtime-rows-for-schema schema rows)
  (if (and rows
           (yuanxu-json-schema-object? schema)
           (pair? rows)
           (null? (cdr rows))
           (pair? (car rows)))
    (let* ((entry (car rows))
           (key (car entry))
           (value (cdr entry))
           (properties (yuanxu-json-schema-object-properties schema))
           (patterns (yuanxu-json-schema-object-pattern-properties schema)))
      (if (and (not (yuanxu-json-schema-static-property-name? properties key))
               (null? (yuanxu-json-schema-matching-runtime-pattern-properties
                       patterns
                       key))
               (list? value))
        value
        rows))
    rows))

;; : (-> YuanxuJsonSchemaObject JsonSchemaRuntimeObjectRows Boolean)
(def (yuanxu-json-schema-object-children-valid? schema value)
  (if (yuanxu-json-schema-object? schema)
    (and (yuanxu-json-schema-object-properties-valid?
          (yuanxu-json-schema-object-properties schema)
          value)
         (yuanxu-json-schema-object-pattern-properties-valid?
          (yuanxu-json-schema-object-properties schema)
          (yuanxu-json-schema-object-pattern-properties schema)
          (yuanxu-json-schema-object-additional-properties schema)
          value))
    #t))

;; yuanxu-json-schema-object-properties-valid?
;;   : (-> [YuanxuJsonSchemaProperty] JsonSchemaRuntimeObjectRows Boolean)
;;   | doc m%
;;       Validate static object properties against the emitted property
;;       predicates while treating missing optional properties as valid.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-object-properties-valid? '() '())
;;       ;; => #t
;;       ```
;;     %
;; Invariants: object validation keeps property, pattern, and additional
;; property checks as composable predicates so policy facts stay inspectable.
(def (yuanxu-json-schema-object-properties-valid? properties value)
  (if (every
       (lambda (property)
         (let* ((name (yuanxu-json-schema-property-name property))
                (entry (yuanxu-json-schema-object-entry value name)))
           (if entry
             ((yuanxu-json-schema-node-predicate
               (yuanxu-json-schema-property-schema property))
              (cdr entry))
             (not (yuanxu-json-schema-property-required? property)))))
       properties)
    #t
    #f))

;; yuanxu-json-schema-object-pattern-properties-valid?
;;   : (-> [YuanxuJsonSchemaProperty] [YuanxuJsonSchemaPatternProperty] JsonSchemaAdditionalProperties JsonSchemaRuntimeObjectRows Boolean)
;;   | doc m%
;;       Validate dynamic object entries against pattern properties, falling
;;       back to the additional-properties policy only when no pattern matches.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-object-pattern-properties-valid? '() '() #t '())
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-json-schema-object-pattern-properties-valid?
      properties pattern-properties additional-properties value)
  (if (every
       (lambda (entry)
         (let* ((key (car entry))
                (matches
                 (yuanxu-json-schema-matching-runtime-pattern-properties
                  pattern-properties
                  key)))
           (if (null? matches)
             (or (yuanxu-json-schema-static-property-name? properties key)
                 (yuanxu-json-schema-additional-runtime-valid?
                  additional-properties
                  (cdr entry)))
             (yuanxu-json-schema-pattern-runtime-valid?
              matches
              (cdr entry)))))
       value)
    #t
    #f))

;; : (-> [YuanxuJsonSchemaPatternProperty] JsonSchemaKey [YuanxuJsonSchemaPatternProperty])
(def (yuanxu-json-schema-matching-runtime-pattern-properties pattern-properties key)
  (let ((runtime-key (yuanxu-json-schema-schema-key->string key)))
    (filter-map
     (lambda (pattern-property)
       (and (yuanxu-json-schema-pattern-runtime-match?
             (yuanxu-json-schema-pattern-property-pattern pattern-property)
             runtime-key)
            pattern-property))
     pattern-properties)))

;; yuanxu-json-schema-pattern-runtime-valid?
;;   : (-> [YuanxuJsonSchemaPatternProperty] JsonSchemaDatum Boolean)
;;   | doc m%
;;       Apply every matched pattern-property predicate to the runtime value and
;;       preserve conjunctive JSON Schema semantics.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-pattern-runtime-valid? '() "value")
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-json-schema-pattern-runtime-valid? pattern-properties value)
  (if (every
       (lambda (pattern-property)
         ((yuanxu-json-schema-node-predicate
           (yuanxu-json-schema-pattern-property-schema pattern-property))
          value))
       pattern-properties)
    #t
    #f))

;; : (-> JsonSchemaAdditionalProperties JsonSchemaDatum Boolean)
(def (yuanxu-json-schema-additional-runtime-valid? additional-properties value)
  (cond
   ((eq? additional-properties #t) #t)
   ((eq? additional-properties #f) #f)
   ((yuanxu-json-schema-node? additional-properties)
    ((yuanxu-json-schema-node-predicate additional-properties) value))
   (else #t)))

;; yuanxu-json-schema-static-property-name?
;;   : (-> [YuanxuJsonSchemaProperty] JsonSchemaKey Boolean)
;;   | doc m%
;;       Detect whether a runtime object key is already covered by a static
;;       property definition before pattern/additional handling runs.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-static-property-name? '() 'missing)
;;       ;; => #f
;;       ```
;;     %
(def (yuanxu-json-schema-static-property-name? properties key)
  (if (find
       (lambda (property)
         (yuanxu-json-schema-schema-key=?
          (yuanxu-json-schema-property-name property)
          key))
       properties)
    #t
    #f))

;; yuanxu-json-schema-object-entry
;;   : (-> JsonSchemaRuntimeObjectRows JsonSchemaKey JsonSchemaObjectEntry)
;;   | doc m%
;;       Return the runtime object entry whose key matches a schema key under
;;       the string-or-symbol normalization rule.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-object-entry '((name . "p")) "name")
;;       ;; => (name . "p")
;;       ```
;;     %
(def (yuanxu-json-schema-object-entry value key)
  (find
   (lambda (entry)
     (and (pair? entry)
          (yuanxu-json-schema-schema-key=? (car entry) key)))
   value))

;; yuanxu-json-schema-node-constraints
;;   : (-> YuanxuJsonSchemaNode Alist)
;;   | doc m%
;;       Read normalized constraint metadata from one schema node.
;;     %
;; yuanxu-json-schema-node-predicate-list
;;   : (-> [YuanxuJsonSchemaNode] [JsonSchemaPredicate])
;;   | doc m%
;;       Project child schema nodes into predicate closures through the contract
;;       SRFI-backed list helper.
;;     %
(def (yuanxu-json-schema-node-predicate-list nodes)
  (yuanxu-contract-project-list
   yuanxu-json-schema-node-predicate
   nodes))

;; yuanxu-json-schema-node-value-kind
;;   : (-> YuanxuJsonSchemaNode Symbol)
;;   | doc m%
;;       Map normalized schema node kinds to generated contract value kinds.
;;     %
(def (yuanxu-json-schema-node-value-kind node)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((eq? kind 'always) 'YuanxuJsonValue)
     ((eq? kind 'never) 'YuanxuJsonNever)
     ((eq? kind 'string) 'String)
     ((eq? kind 'number) 'Number)
     ((eq? kind 'integer) 'Integer)
     ((eq? kind 'boolean) 'Boolean)
     ((eq? kind 'null) 'YuanxuJsonNull)
     ((eq? kind 'object) 'YuanxuJsonObject)
     ((eq? kind 'array) 'List)
     ((eq? kind 'nullable) 'YuanxuJsonNullable)
     ((eq? kind 'enum) 'YuanxuJsonEnum)
     ((eq? kind 'const) 'YuanxuJsonConst)
     ((eq? kind 'one-of) 'YuanxuJsonOneOf)
     (else 'YuanxuJsonValue))))

;; yuanxu-json-schema-node-predicate-key
;;   : (-> YuanxuJsonSchemaNode Symbol)
;;   | doc m%
;;       Map normalized schema node kinds to generated predicate metadata keys.
;;     %
(def (yuanxu-json-schema-node-predicate-key node)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((eq? kind 'always) 'yuanxu-json-schema-any?)
     ((eq? kind 'never) 'yuanxu-json-schema-never?)
     ((eq? kind 'string) 'string?)
     ((eq? kind 'number) 'number?)
     ((eq? kind 'integer) 'yuanxu-json-schema-integer-value?)
     ((eq? kind 'boolean) 'boolean?)
     ((eq? kind 'null) 'yuanxu-json-schema-null?)
     ((eq? kind 'object) 'yuanxu-json-schema-json-object-value?)
     ((eq? kind 'array) 'yuanxu-json-schema-json-array-value?)
     ((eq? kind 'nullable) 'yuanxu-json-schema-nullable-generated?)
     ((eq? kind 'enum) 'yuanxu-json-schema-enum-generated?)
     ((eq? kind 'const) 'yuanxu-json-schema-const-generated?)
     ((eq? kind 'any-of) 'yuanxu-json-schema-any-of-generated?)
     ((eq? kind 'all-of) 'yuanxu-json-schema-all-of-generated?)
     ((eq? kind 'one-of) 'yuanxu-json-schema-one-of-generated?)
     (else 'yuanxu-json-schema-any?))))

;; yuanxu-json-schema-node-predicate
;;   : (-> YuanxuJsonSchemaNode JsonSchemaPredicate)
;;   | result: runtime predicate used by generated slot contracts
;;   | doc m%
;;       Predicate generation is the only runtime-testing boundary in the JSON
;;       Schema bridge; contract metadata still carries the normalized IR.
;;       # Examples
;;       ```scheme
;;       ((yuanxu-json-schema-node-predicate node) value)
;;       ;; => boolean
;;       ```
;;     %
(def (yuanxu-json-schema-node-predicate node)
  (let (kind (yuanxu-json-schema-node-kind node))
    (yuanxu-json-schema-apply-node-constraints
     node
     (cond
      ((eq? kind 'always) yuanxu-json-schema-any?)
      ((eq? kind 'never) (lambda (_value) #f))
     ((eq? kind 'string) (yuanxu-json-schema-string-predicate node))
     ((eq? kind 'number) (yuanxu-json-schema-number-predicate node number?))
     ((eq? kind 'integer)
      (yuanxu-json-schema-number-predicate
       node
       yuanxu-json-schema-integer-value?))
      ((eq? kind 'boolean) boolean?)
      ((eq? kind 'null) yuanxu-json-schema-null?)
     ((eq? kind 'object) (yuanxu-json-schema-object-predicate node))
      ((eq? kind 'array)
       (let (items (yuanxu-json-schema-node-value node))
         (if (list? items)
           (let (predicates (map yuanxu-json-schema-node-predicate items))
             (lambda (value)
               (and (or (list? value) (vector? value))
                    (let loop ((ps predicates) (vs (if (vector? value) (vector->list value) value)))
                      (or (null? ps) (null? vs)
                          (and ((car ps) (car vs)) (loop (cdr ps) (cdr vs))))))))
           (yuanxu-json-schema-array-predicate
            (yuanxu-json-schema-node-predicate items)
            (yuanxu-json-schema-node-metadata node)))))
      ((eq? kind 'const)
       (yuanxu-json-schema-const-predicate
        (yuanxu-json-schema-node-value node)))
      ((eq? kind 'enum)
       (yuanxu-json-schema-enum-predicate
        (yuanxu-json-schema-node-value node)))
      ((eq? kind 'nullable)
       (yuanxu-json-schema-nullable-predicate
        (yuanxu-json-schema-node-predicate
         (yuanxu-json-schema-node-value node))))
      ((eq? kind 'any-of)
       (yuanxu-predicate-or
        (yuanxu-json-schema-node-predicate-list
         (yuanxu-json-schema-node-value node))))
      ((eq? kind 'all-of)
       (yuanxu-predicate-and
        (yuanxu-json-schema-node-predicate-list
         (yuanxu-json-schema-node-value node))))
      ((eq? kind 'one-of)
       (yuanxu-predicate-exactly-one
        (yuanxu-json-schema-node-predicate-list
         (yuanxu-json-schema-node-value node))))
      (else yuanxu-json-schema-any?))
     yuanxu-json-schema-json-array-value?)))

;; : (-> JsonSchemaDatum JsonSchemaDatum)
