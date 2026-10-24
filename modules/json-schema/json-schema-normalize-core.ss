;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: owns the core JSON Schema normalization parser entry points and
;;; parser registry plumbing used by the contract harness.
;;; Invariant: callers should trust this owner for parser-visible diagnostics
;;; and normalized IR construction, while emit/runtime behavior remains outside
;;; this module.

(import (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node-record
                 yuanxu-json-schema-diagnostic-record)
        (only-in "./functional.ss"
                 yuanxu-contract-json-object?
                 yuanxu-contract-json-array->list
                 yuanxu-contract-object-ref
                 yuanxu-contract-string-drop-prefix
                 yuanxu-contract-filter-map
                 yuanxu-contract-map-pair-with-diagnostics))

(export +yuanxu-json-schema-missing+
        yuanxu-json-schema-parse
        yuanxu-json-schema-parse/context
        yuanxu-json-schema-local-definition-name
        yuanxu-json-schema-register-object-parsers!)

;; Engineering boundary: this owner is the JSON Schema parser dispatch core.
;; Keep object/array specialization behind registered parser callbacks and keep
;; list traversal in SRFI-1/project contract helpers so diagnostics remain
;; stable for generated facts.

;; : JsonSchemaMissingSentinel
(def +yuanxu-json-schema-missing+ (list 'yuanxu-json-schema-missing))
;; : MaybeProcedure
(def +yuanxu-json-schema-object-parser+ #f)
;; : MaybeProcedure
(def +yuanxu-json-schema-array-parser+ #f)

;; : (-> Procedure Procedure Void)
(def (yuanxu-json-schema-register-object-parsers! object-parser array-parser)
  (set! +yuanxu-json-schema-object-parser+ object-parser)
  (set! +yuanxu-json-schema-array-parser+ array-parser))

;; : (-> Object Diagnostics Pair)
(def (yuanxu-json-schema-result node diagnostics) (cons node diagnostics))

;; : (-> Symbol Symbol String Object Alist JsonSchemaDiagnostic)
(def (yuanxu-json-schema-diagnostic severity reason message value context)
  (yuanxu-json-schema-diagnostic-record severity reason message value context))

;; : (-> Symbol Object Alist Pair)
(def (yuanxu-json-schema-node-result kind value context)
  (yuanxu-json-schema-result
   (yuanxu-json-schema-node-record kind value context)
   '()))

;; : (-> Symbol Object Alist Symbol String Pair)
(def (yuanxu-json-schema-invalid-result kind value context reason message)
  (yuanxu-json-schema-result
   (yuanxu-json-schema-node-record kind value context)
   (list (yuanxu-json-schema-diagnostic
          'warning reason message value context))))

;; : (-> Object Pair)
(def (yuanxu-json-schema-parse schema)
  (yuanxu-json-schema-parse/context schema '()))

;; : (-> Object Alist Pair)
(def (yuanxu-json-schema-parse/context schema context)
  (cond
   ((yuanxu-json-schema-json-object? schema)
    (yuanxu-json-schema-parse-object schema context))
   ((boolean? schema)
    (yuanxu-json-schema-node-result 'boolean-schema schema context))
   (else
    (yuanxu-json-schema-invalid-result
     'invalid schema context 'invalid-schema
     "JSON Schema entry must be an object or boolean."))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-object schema context)
  (let ((ref (yuanxu-contract-object-ref schema "$ref" +yuanxu-json-schema-missing+)))
    (if (eq? ref +yuanxu-json-schema-missing+)
      (yuanxu-json-schema-parse-non-ref-object schema context)
      (if (string? ref)
        (yuanxu-json-schema-node-result
         'ref ref (cons (cons 'schema schema) context))
        (yuanxu-json-schema-invalid-result
         'invalid-ref ref context 'invalid-ref
         "JSON Schema $ref must be a string.")))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-non-ref-object schema context)
  (let* ((parsed (yuanxu-json-schema-parse-non-ref-base schema context))
         (choices (yuanxu-contract-object-ref schema "enum" +yuanxu-json-schema-missing+)))
    (if (eq? choices +yuanxu-json-schema-missing+)
      parsed
      (let (items (yuanxu-json-schema-array-value choices))
        ;; Reuse the existing intersection and enum evaluators. Do not silently
        ;; store enum as metadata while accepting every value of its base type.
        ;; Composite/null enum equality needs a separate JSON-semantic adapter.
        (if (and (pair? items)
                 (andmap (lambda (item) (or (string? item) (number? item) (boolean? item))) items))
          (yuanxu-json-schema-result
            (yuanxu-json-schema-node-record 'all-of
              (list (car parsed) (yuanxu-json-schema-node-record 'enum items context)) context)
            (cdr parsed))
          (yuanxu-json-schema-result (car parsed)
            (cons (yuanxu-json-schema-diagnostic 'warning 'unsupported-enum
                    "enum requires a nonempty array of supported scalar values." choices context)
                  (cdr parsed))))))))

(def (yuanxu-json-schema-parse-non-ref-base schema context)
  (let ((logical (yuanxu-json-schema-parse-logical schema context)))
    (if logical
      logical
      (let ((declared-type
             (yuanxu-contract-object-ref schema "type" +yuanxu-json-schema-missing+)))
        (if (eq? declared-type +yuanxu-json-schema-missing+)
          (yuanxu-json-schema-parse-implicit schema context)
          (yuanxu-json-schema-parse-type declared-type schema context))))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-implicit schema context)
  (cond
   ((not (eq? (yuanxu-contract-object-ref schema "properties" +yuanxu-json-schema-missing+)
              +yuanxu-json-schema-missing+))
    (yuanxu-json-schema-object-dispatch schema context))
   ((not (eq? (yuanxu-contract-object-ref schema "additionalProperties" +yuanxu-json-schema-missing+)
              +yuanxu-json-schema-missing+))
    (yuanxu-json-schema-object-dispatch schema context))
   ((not (eq? (yuanxu-contract-object-ref schema "patternProperties" +yuanxu-json-schema-missing+)
              +yuanxu-json-schema-missing+))
    (yuanxu-json-schema-object-dispatch schema context))
   ((not (eq? (yuanxu-contract-object-ref schema "items" +yuanxu-json-schema-missing+)
              +yuanxu-json-schema-missing+))
    (yuanxu-json-schema-array-dispatch schema context))
   (else
    (yuanxu-json-schema-node-result
     'any schema (yuanxu-json-schema-schema-metadata schema context)))))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-object-dispatch schema context)
  (if +yuanxu-json-schema-object-parser+
    (+yuanxu-json-schema-object-parser+ schema context)
    (yuanxu-json-schema-invalid-result
     'object schema context 'object-parser-missing
     "JSON Schema object parser is not registered.")))

;; : (-> JsonObject Alist Pair)
(def (yuanxu-json-schema-array-dispatch schema context)
  (if +yuanxu-json-schema-array-parser+
    (+yuanxu-json-schema-array-parser+ schema context)
    (yuanxu-json-schema-invalid-result
     'array schema context 'array-parser-missing
     "JSON Schema array parser is not registered.")))

;; : (-> JsonObject Alist (U Pair False))
(def (yuanxu-json-schema-parse-logical schema context)
  (let ((all-of (yuanxu-contract-object-ref schema "allOf" +yuanxu-json-schema-missing+))
        (any-of (yuanxu-contract-object-ref schema "anyOf" +yuanxu-json-schema-missing+))
        (one-of (yuanxu-contract-object-ref schema "oneOf" +yuanxu-json-schema-missing+))
        (not-schema (yuanxu-contract-object-ref schema "not" +yuanxu-json-schema-missing+)))
    (cond
     ((not (eq? all-of +yuanxu-json-schema-missing+))
      (yuanxu-json-schema-parse-logical-list 'all-of all-of context))
     ((not (eq? any-of +yuanxu-json-schema-missing+))
      (yuanxu-json-schema-parse-logical-list 'any-of any-of context))
     ((not (eq? one-of +yuanxu-json-schema-missing+))
      (yuanxu-json-schema-parse-logical-list 'one-of one-of context))
     ((not (eq? not-schema +yuanxu-json-schema-missing+))
      (let ((parsed (yuanxu-json-schema-parse/context
                     not-schema (cons (cons 'logical 'not) context))))
        (yuanxu-json-schema-result
         (yuanxu-json-schema-node-record 'not (car parsed) context)
         (cdr parsed))))
     (else #f))))

;; Boundary: logical arrays are pure parser projections, not runtime
;; validation; keep index context aligned with encounter order for proof facts.
;; yuanxu-json-schema-parse-logical-list
;;   : (-> Symbol JsonArray Alist Pair)
;;   | doc m%
;;       Parse allOf/anyOf/oneOf entries through the shared functional
;;       diagnostic mapper. The mapper preserves encounter order while carrying
;;       the per-entry index required by downstream facts.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-parse-logical-list 'all-of schemas '())
;;       ;; => (node . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-parse-logical-list kind value context)
  (let ((items (yuanxu-json-schema-array-value value)))
    (if (list? items)
      (let* ((indexed-items (map cons items (iota (length items))))
             (parsed-items
              (yuanxu-contract-map-pair-with-diagnostics
               (lambda (entry)
                 (let ((parsed (yuanxu-json-schema-parse/context
                                (car entry)
                                (cons (cons 'index (cdr entry))
                                      (cons (cons 'logical kind) context)))))
                   (cons (car parsed) (cdr parsed))))
               indexed-items
               '())))
        (yuanxu-json-schema-result
         (yuanxu-json-schema-node-record kind (car parsed-items) context)
         (cdr parsed-items)))
      (yuanxu-json-schema-invalid-result
       'invalid value context 'invalid-logical-list
       "JSON Schema logical keyword must contain an array."))))

;; : (-> Object JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-type declared-type schema context)
  (cond
   ((string? declared-type)
    (yuanxu-json-schema-parse-type-name
     (string->symbol declared-type) schema context))
   ((list? (yuanxu-json-schema-array-value declared-type))
    (yuanxu-json-schema-parse-type-list
     (yuanxu-json-schema-array-value declared-type) schema context))
   (else
    (yuanxu-json-schema-invalid-result
     'invalid declared-type context 'invalid-type
     "JSON Schema type must be a string or string array."))))

;; Boundary: invalid type-array entries become diagnostics, not exceptions.
;; Invariant: the one-of node only contains successfully parsed type nodes.
;; yuanxu-json-schema-parse-type-list
;;   : (-> [Object] JsonObject Alist Pair)
;;   | doc m%
;;       Parse a JSON Schema type array as a one-of node. Invalid entries become
;;       diagnostics, while missing nodes are filtered through the project
;;       contract helper instead of a local accumulator loop.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-parse-type-list '("string" "number") schema '())
;;       ;; => (one-of-node . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-parse-type-list type-list schema context)
  (let ((parsed-types
         (yuanxu-contract-map-pair-with-diagnostics
          (lambda (entry)
            (if (string? entry)
              (let ((parsed (yuanxu-json-schema-parse-type-name
                             (string->symbol entry) schema context)))
                (cons (car parsed) (cdr parsed)))
              (cons +yuanxu-json-schema-missing+
                    (list (yuanxu-json-schema-diagnostic
                           'warning 'invalid-type-entry
                           "JSON Schema type array entry must be a string."
                           entry context)))))
          type-list
          '())))
    (yuanxu-json-schema-result
     (yuanxu-json-schema-node-record
      'one-of
      (yuanxu-contract-filter-map
       (lambda (node)
         (and (not (eq? node +yuanxu-json-schema-missing+)) node))
       (car parsed-types))
      context)
     (cdr parsed-types))))

;; : (-> Symbol JsonObject Alist Pair)
(def (yuanxu-json-schema-parse-type-name type-name schema context)
  (case type-name
    ((object) (yuanxu-json-schema-object-dispatch schema context))
    ((array) (yuanxu-json-schema-array-dispatch schema context))
    ((string number integer boolean null)
     (yuanxu-json-schema-scalar-result type-name schema context))
    (else
     (yuanxu-json-schema-invalid-result
      'unknown-type type-name context 'unknown-type
      "JSON Schema type is not supported."))))

;; : (-> Symbol JsonObject Alist Pair)
(def (yuanxu-json-schema-scalar-result type-name schema context)
  (yuanxu-json-schema-result
   (yuanxu-json-schema-node-record
    type-name schema (yuanxu-json-schema-schema-metadata schema context))
   (yuanxu-json-schema-constraint-diagnostics schema context)))

;; : (-> JsonObject Alist Diagnostics)
(def (yuanxu-json-schema-constraint-diagnostics schema context)
  (append
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "minLength" context)
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "maxLength" context)
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "minItems" context)
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "maxItems" context)
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "minProperties" context)
   (yuanxu-json-schema-nonnegative-integer-diagnostic schema "maxProperties" context)
   (yuanxu-json-schema-number-diagnostic schema "minimum" context)
   (yuanxu-json-schema-number-diagnostic schema "maximum" context)
   (yuanxu-json-schema-number-diagnostic schema "exclusiveMinimum" context)
   (yuanxu-json-schema-number-diagnostic schema "exclusiveMaximum" context)
   (yuanxu-json-schema-number-diagnostic schema "multipleOf" context)
   (yuanxu-json-schema-string-diagnostic schema "pattern" context)
   (yuanxu-json-schema-string-diagnostic schema "format" context)))

;; : (-> JsonObject String Alist Diagnostics)
(def (yuanxu-json-schema-nonnegative-integer-diagnostic schema keyword context)
  (let ((value (yuanxu-contract-object-ref schema keyword +yuanxu-json-schema-missing+)))
    (cond
     ((eq? value +yuanxu-json-schema-missing+) '())
     ((and (integer? value) (>= value 0)) '())
     (else
      (list (yuanxu-json-schema-diagnostic
             'warning 'invalid-constraint-value
             "JSON Schema constraint must be a non-negative integer."
             value
             (cons (cons 'keyword keyword) context)))))))

;; : (-> JsonObject String Alist Diagnostics)
(def (yuanxu-json-schema-number-diagnostic schema keyword context)
  (let ((value (yuanxu-contract-object-ref schema keyword +yuanxu-json-schema-missing+)))
    (cond
     ((eq? value +yuanxu-json-schema-missing+) '())
     ((number? value) '())
     (else
      (list (yuanxu-json-schema-diagnostic
             'warning 'invalid-constraint-value
             "JSON Schema constraint must be a number."
             value
             (cons (cons 'keyword keyword) context)))))))

;; : (-> JsonObject String Alist Diagnostics)
(def (yuanxu-json-schema-string-diagnostic schema keyword context)
  (let ((value (yuanxu-contract-object-ref schema keyword +yuanxu-json-schema-missing+)))
    (cond
     ((eq? value +yuanxu-json-schema-missing+) '())
     ((string? value) '())
     (else
      (list (yuanxu-json-schema-diagnostic
             'warning 'invalid-constraint-value
             "JSON Schema constraint must be a string."
             value
             (cons (cons 'keyword keyword) context)))))))

;; : (-> JsonObject Alist Alist)
(def (yuanxu-json-schema-schema-metadata schema context)
  (let (constraints
        (yuanxu-json-schema-filter-missing
         (list (cons 'minLength (yuanxu-contract-object-ref schema "minLength" +yuanxu-json-schema-missing+))
               (cons 'maxLength (yuanxu-contract-object-ref schema "maxLength" +yuanxu-json-schema-missing+))
               (cons 'minimum (yuanxu-contract-object-ref schema "minimum" +yuanxu-json-schema-missing+))
               (cons 'maximum (yuanxu-contract-object-ref schema "maximum" +yuanxu-json-schema-missing+))
               (cons 'exclusiveMinimum (yuanxu-contract-object-ref schema "exclusiveMinimum" +yuanxu-json-schema-missing+))
               (cons 'exclusiveMaximum (yuanxu-contract-object-ref schema "exclusiveMaximum" +yuanxu-json-schema-missing+))
               (cons 'minItems (yuanxu-contract-object-ref schema "minItems" +yuanxu-json-schema-missing+))
               (cons 'maxItems (yuanxu-contract-object-ref schema "maxItems" +yuanxu-json-schema-missing+))
               (cons 'minProperties (yuanxu-contract-object-ref schema "minProperties" +yuanxu-json-schema-missing+))
               (cons 'maxProperties (yuanxu-contract-object-ref schema "maxProperties" +yuanxu-json-schema-missing+))
               (cons 'pattern (yuanxu-contract-object-ref schema "pattern" +yuanxu-json-schema-missing+)))))
    (yuanxu-json-schema-filter-missing
     (list (cons 'context context)
           (cons 'title (yuanxu-contract-object-ref schema "title" +yuanxu-json-schema-missing+))
           (cons 'description (yuanxu-contract-object-ref schema "description" +yuanxu-json-schema-missing+))
           (cons 'format (yuanxu-contract-object-ref schema "format" +yuanxu-json-schema-missing+))
           (cons 'enum (yuanxu-contract-object-ref schema "enum" +yuanxu-json-schema-missing+))
           (cons 'const (yuanxu-contract-object-ref schema "const" +yuanxu-json-schema-missing+))
           (cons 'constraints constraints)))))

;; Boundary: metadata absence is represented only by the shared sentinel.
;; Invariant: explicit false/null-like values must survive this projection.
;; yuanxu-json-schema-filter-missing
;;   : (-> Alist Alist)
;;   | doc m%
;;       Remove entries whose value is the JSON Schema missing sentinel while
;;       preserving explicit false/null-like values for metadata and proofs.
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

;; : (-> String MaybeSymbol)
(def (yuanxu-json-schema-local-definition-name reference)
  (and (string? reference)
       (let ((definitions-name
              (yuanxu-contract-string-drop-prefix "#/definitions/" reference))
             (defs-name
              (yuanxu-contract-string-drop-prefix "#/$defs/" reference)))
         (let ((name (or definitions-name defs-name)))
           (and name (not (string=? name "")) (string->symbol name))))))

;; yuanxu-json-schema-json-object?
;;   : (-> Object Boolean)
;;   | doc m%
;;       Accept JSON-like alists whose keys are strings or symbols. This guards
;;       the parser against treating arbitrary pair lists as schema objects
;;       while keeping the scan in a declarative SRFI-1 predicate.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-json-object? '(("type" . "string")))
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
