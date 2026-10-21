;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: owns object/property/pattern-property parsing for normalized JSON
;;; Schema IR and delegates shared registry behavior to normalize-core.
;;; Invariant: parser-owned facts from this owner describe schema shape and
;;; diagnostics only; reference resolution and runtime predicate emission live
;;; in sibling modules.

(import (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node-record
                 yuanxu-json-schema-object-record
                 yuanxu-json-schema-property-record
                 yuanxu-json-schema-pattern-property-record
                 yuanxu-json-schema-diagnostic-record)
        (only-in "./functional.ss"
                 yuanxu-contract-json-object?
                 yuanxu-contract-json-array->list
                 yuanxu-contract-key->string
                 yuanxu-contract-key->symbol
                 yuanxu-contract-object-ref
                 yuanxu-contract-filter-map
                 yuanxu-contract-member?
                 yuanxu-contract-map-pair-with-diagnostics)
        (only-in "./json-schema-normalize-core.ss"
                 +yuanxu-json-schema-missing+
                 yuanxu-json-schema-parse/context
                 yuanxu-json-schema-register-object-parsers!))

(export yuanxu-json-schema-parse-array-schema
        yuanxu-json-schema-parse-object-schema
        yuanxu-json-schema-parse-definitions)

;; Engineering boundary: this owner parses object/array specializations after
;; the core dispatcher has selected the branch. Keep tuple, property, and
;; definition walks on shared contract mappers so contributed schemas produce
;; deterministic nodes and diagnostics.

;; : (-> Object Diagnostics Pair)
(def (yuanxu-json-schema-result node diagnostics) (cons node diagnostics))

;; : (-> Symbol Symbol String Object Alist JsonSchemaDiagnostic)
(def (yuanxu-json-schema-diagnostic severity reason message value context)
  (yuanxu-json-schema-diagnostic-record severity reason message value context))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-array-schema schema context)
  (let ((unique (yuanxu-contract-object-ref schema "uniqueItems" +yuanxu-json-schema-missing+))
        (parsed (yuanxu-json-schema-parse-array-shape schema context)))
    (if (or (eq? unique +yuanxu-json-schema-missing+) (boolean? unique))
      parsed
      (cons (car parsed)
            (cons (yuanxu-json-schema-diagnostic
                    'warning 'invalid-constraint-value
                    "JSON Schema uniqueItems must be a boolean" unique context)
                  (cdr parsed))))))

(def (yuanxu-json-schema-parse-array-shape schema context)
  (let ((items (yuanxu-contract-object-ref schema "items" +yuanxu-json-schema-missing+)))
    (cond
     ((eq? items +yuanxu-json-schema-missing+)
      (yuanxu-json-schema-result
       (yuanxu-json-schema-node-record
        'array
        (yuanxu-json-schema-node-record 'any '() (list (cons 'implicit #t)))
        (yuanxu-json-schema-array-metadata schema context))
       '()))
     ((and (not (yuanxu-json-schema-json-object?
                 (yuanxu-json-schema-array-value items)))
           (list? (yuanxu-json-schema-array-value items)))
      (yuanxu-json-schema-parse-tuple-schema schema items context))
     (else
      (let ((parsed (yuanxu-json-schema-parse/context
                     items
                     (cons (cons 'slot 'items) context))))
        (yuanxu-json-schema-result
         (yuanxu-json-schema-node-record
          'array
          (car parsed)
          (yuanxu-json-schema-array-metadata schema context))
         (cdr parsed)))))))

;; Boundary: tuple schemas are parsed as indexed item projections, not generic
;; array validation; diagnostics stay tied to each tuple position.
;; yuanxu-json-schema-parse-tuple-schema
;;   : (-> JsonObject JsonArray Alist Pair)
;;   | doc m%
;;       Parse tuple-style `items` schemas with the shared diagnostic mapper.
;;       The indexed projection is a pure value transform and keeps tuple node
;;       order stable for generated facts.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-parse-tuple-schema schema items '())
;;       ;; => (array-node . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-parse-tuple-schema schema items context)
  (let* ((item-list (yuanxu-json-schema-array-value items))
         (indexed-items (map cons item-list (iota (length item-list))))
         (parsed-items
          (yuanxu-contract-map-pair-with-diagnostics
           (lambda (entry)
             (let ((parsed (yuanxu-json-schema-parse/context
                            (car entry)
                            (list (cons 'slot 'items)
                                  (cons 'index (cdr entry))))))
               (cons (car parsed) (cdr parsed))))
           indexed-items
           '())))
    (yuanxu-json-schema-result
     (yuanxu-json-schema-node-record
      'array
      (car parsed-items)
      (yuanxu-json-schema-array-metadata schema context))
     (cdr parsed-items))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-object-schema schema context)
  (let* ((required (yuanxu-json-schema-required-symbols schema))
         (properties-result
          (yuanxu-json-schema-parse-properties schema required context))
         (additional-result
          (yuanxu-json-schema-parse-additional-properties schema context))
         (patterns-result
          (yuanxu-json-schema-parse-pattern-properties schema context))
         (metadata (yuanxu-json-schema-object-metadata schema context)))
    (yuanxu-json-schema-result
     (yuanxu-json-schema-node-record
      'object
      (yuanxu-json-schema-object-record
       (car properties-result)
       (if (pair? additional-result) (car additional-result) additional-result)
       (car patterns-result)
       metadata)
      metadata)
     (append (cdr properties-result)
             (if (pair? additional-result) (cdr additional-result) '())
             (cdr patterns-result)))))

;; Boundary: this helper projects required names only; malformed required
;; entries are left for validation diagnostics instead of parse-time failure.
;; yuanxu-json-schema-required-symbols
;;   : (-> JsonObject [Symbol])
;;   | doc m%
;;       Project the JSON Schema `required` array into symbols. Non-string
;;       entries are ignored here because diagnostics are emitted by the schema
;;       validation layer.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-required-symbols schema)
;;       ;; => (name email)
;;       ```
;;     %
(def (yuanxu-json-schema-required-symbols schema)
  (let ((required (yuanxu-contract-object-ref schema "required" +yuanxu-json-schema-missing+)))
    (if (list? (yuanxu-json-schema-array-value required))
      (yuanxu-contract-filter-map
       (lambda (entry)
         (and (string? entry) (string->symbol entry)))
       (yuanxu-json-schema-array-value required))
      '())))

;; Boundary: required-slot lookup is a contract membership check over already
;; normalized symbols, so object parsing does not duplicate list traversal.
;; yuanxu-json-schema-required-slot?
;;   : (-> Symbol [Symbol] Boolean)
;;   | doc m%
;;       Check whether an object property is declared in the required symbol
;;       list using the project contract membership helper.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-required-slot? 'name '(name email))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-json-schema-required-slot? name required)
  (yuanxu-contract-member? name required))

;; : (-> JsonObject [Symbol] Alist Pair)
(def (yuanxu-json-schema-parse-properties schema required context)
  (let ((properties
         (yuanxu-contract-object-ref schema "properties" +yuanxu-json-schema-missing+)))
    (cond
     ((eq? properties +yuanxu-json-schema-missing+) (cons '() '()))
     ((yuanxu-json-schema-json-object? properties)
      (yuanxu-json-schema-parse-property-pairs properties required context))
     (else
      (cons '()
            (list (yuanxu-json-schema-diagnostic
                   'warning 'invalid-properties
                   "JSON Schema properties must be an object."
                   properties context)))))))

;; : (-> JsonObject [Symbol] Alist Pair)
(import (only-in :std/text/pregexp pregexp))

;; : (-> JsonSchemaPairEntry JsonSchemaPairEntryValue)
(def (yuanxu-json-schema-pair-entry-value entry)
  (let (tail (cdr entry))
    (if (and (pair? tail)
             (null? (cdr tail))
             (not (yuanxu-json-schema-json-object? tail))
             (yuanxu-json-schema-json-object? (car tail)))
      (car tail)
      tail)))

;; : (-> Alist [Symbol] Object Object)
(def (yuanxu-json-schema-parse-property-pairs properties required context)
  (yuanxu-contract-map-pair-with-diagnostics
   (lambda (entry)
     (let* ((name (car entry))
        (value (yuanxu-json-schema-pair-entry-value entry))
            (slot (yuanxu-contract-key->symbol name))
            (parsed (yuanxu-json-schema-parse/context
                     value
                     (cons (cons 'property slot) context))))
       (cons (yuanxu-json-schema-property-record
              slot
              (car parsed)
              (yuanxu-json-schema-required-slot? slot required)
              (yuanxu-json-schema-schema-description value)
              '())
             (cdr parsed))))
   properties
   '()))

;; : (-> JsonObject Alist (U Boolean Pair))
(def (yuanxu-json-schema-parse-additional-properties schema context)
  (let ((value
         (yuanxu-contract-object-ref schema "additionalProperties" +yuanxu-json-schema-missing+)))
    (cond
     ((eq? value +yuanxu-json-schema-missing+) #t)
     ((boolean? value) value)
     ((yuanxu-json-schema-json-object? value)
      (yuanxu-json-schema-parse/context
       value
       (cons (cons 'slot 'additional-properties) context)))
     (else
      (cons #f
            (list (yuanxu-json-schema-diagnostic
                   'warning 'invalid-additional-properties
                   "JSON Schema additionalProperties must be boolean or object."
                   value context)))))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-pattern-properties schema context)
  (let ((patterns
         (yuanxu-contract-object-ref schema "patternProperties" +yuanxu-json-schema-missing+)))
    (cond
     ((eq? patterns +yuanxu-json-schema-missing+) (cons '() '()))
     ((yuanxu-json-schema-json-object? patterns)
      (yuanxu-json-schema-parse-pattern-property-pairs patterns context))
     (else
      (cons '()
            (list (yuanxu-json-schema-diagnostic
                   'warning 'invalid-pattern-properties
                   "JSON Schema patternProperties must be an object."
                   patterns context)))))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-pattern-property-pairs patterns context)
  (yuanxu-contract-map-pair-with-diagnostics
   (lambda (entry)
     (let* ((name (car entry))
        (value (yuanxu-json-schema-pair-entry-value entry))
            (parsed (yuanxu-json-schema-parse/context
                     value
                     (cons (cons 'pattern-property
                                 (yuanxu-contract-key->string name))
                           context))))
       (cons (yuanxu-json-schema-pattern-property-record
              (yuanxu-contract-key->string name)
         (pregexp (yuanxu-contract-key->string name))
              (car parsed))
             (cdr parsed))))
   patterns
   '()))

;; : (-> JsonObject Pair)
(def (yuanxu-json-schema-parse-definitions schema)
  (let ((definitions
         (yuanxu-contract-object-ref schema "definitions" +yuanxu-json-schema-missing+))
        (defs
         (yuanxu-contract-object-ref schema "$defs" +yuanxu-json-schema-missing+)))
    (let ((definitions-result
           (if (yuanxu-json-schema-json-object? definitions)
             (yuanxu-json-schema-parse-definition-pairs definitions 'definitions)
             (cons '() '())))
          (defs-result
           (if (yuanxu-json-schema-json-object? defs)
             (yuanxu-json-schema-parse-definition-pairs defs '$defs)
             (cons '() '()))))
      (cons (append (car definitions-result) (car defs-result))
            (append (cdr definitions-result) (cdr defs-result))))))

;; : (-> JsonObject Symbol Pair)
(def (yuanxu-json-schema-parse-definition-pairs definitions slot)
  (yuanxu-contract-map-pair-with-diagnostics
   (lambda (entry)
     (let* ((name (car entry))
        (value (yuanxu-json-schema-pair-entry-value entry))
            (parsed (yuanxu-json-schema-parse/context
                     value
                     (list (cons 'definition (yuanxu-contract-key->symbol name))
                           (cons 'slot slot)))))
       (cons (cons (yuanxu-contract-key->symbol name) (car parsed))
             (cdr parsed))))
   definitions
   '()))

;; : (-> JsonObject Alist Alist)
(def (yuanxu-json-schema-array-metadata schema context)
  (let (constraints
        (yuanxu-json-schema-filter-missing
         (list (cons 'minItems
                     (yuanxu-contract-object-ref schema "minItems" +yuanxu-json-schema-missing+))
               (cons 'maxItems
                     (yuanxu-contract-object-ref schema "maxItems" +yuanxu-json-schema-missing+))
               (cons 'uniqueItems
                     (yuanxu-contract-object-ref schema "uniqueItems" +yuanxu-json-schema-missing+)))))
    (yuanxu-json-schema-filter-missing
     (list (cons 'context context)
           (cons 'constraints constraints)))))

;; : (-> JsonObject Alist Alist)
(def (yuanxu-json-schema-object-metadata schema context)
  (let (constraints
        (yuanxu-json-schema-filter-missing
         (list (cons 'minProperties
                     (yuanxu-contract-object-ref schema "minProperties" +yuanxu-json-schema-missing+))
               (cons 'maxProperties
                     (yuanxu-contract-object-ref schema "maxProperties" +yuanxu-json-schema-missing+)))))
    (yuanxu-json-schema-filter-missing
     (list (cons 'context context)
           (cons 'title
                 (yuanxu-contract-object-ref schema "title" +yuanxu-json-schema-missing+))
           (cons 'description
                 (yuanxu-contract-object-ref schema "description" +yuanxu-json-schema-missing+))
           (cons 'constraints constraints)))))

;; : (-> Object Object)
(def (yuanxu-json-schema-schema-description schema)
  (if (yuanxu-json-schema-json-object? schema)
    (yuanxu-contract-object-ref schema "description" +yuanxu-json-schema-missing+)
    +yuanxu-json-schema-missing+))

;; yuanxu-json-schema-json-object?
;;   : (-> Object Boolean)
;;   | doc m%
;;       Accept JSON-like alists whose keys are strings or symbols before
;;       parsing object-specific schema slots. The predicate uses SRFI-1 `every`
;;       instead of a local accumulator loop.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-json-object? '(("properties" . ())))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-json-schema-json-object? value)
  (and (yuanxu-contract-json-object? value)
       (every (lambda (entry)
                (and (pair? entry)
                     (let ((key (car entry)))
                       (or (string? key) (symbol? key)))))
              value)))

;; : (-> Object [Object])
(def (yuanxu-json-schema-array-value value)
  (let ((items (yuanxu-contract-json-array->list value)))
    (if (and (pair? items)
             (null? (cdr items))
             (list? (car items))
             (not (yuanxu-json-schema-json-object? (car items))))
      (car items)
      items)))

;; Boundary: parse metadata removes only the shared missing sentinel.
;; Invariant: explicit schema values such as #f must remain visible.
;; yuanxu-json-schema-filter-missing
;;   : (-> Alist Alist)
;;   | doc m%
;;       Remove metadata entries that still hold the JSON Schema missing
;;       sentinel. This keeps metadata declaration code compact and makes
;;       absence explicit for downstream facts.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-filter-missing `((title . ,+yuanxu-json-schema-missing+)))
;;       ;; => ()
;;       ```
;;     %
(def (yuanxu-json-schema-filter-missing entries)
  (yuanxu-contract-filter-map
   (lambda (entry)
     (and (not (eq? (cdr entry) +yuanxu-json-schema-missing+)) entry))
   entries))

(yuanxu-json-schema-register-object-parsers!
 yuanxu-json-schema-parse-object-schema
 yuanxu-json-schema-parse-array-schema)
