;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: JSON Schema normalized IR for contract generation.
;;; Invariant: this file owns data shape only; parsing and emission live in
;;; neighboring owners.

(export make-yuanxu-json-schema-node
        yuanxu-json-schema-node?
        yuanxu-json-schema-node-kind
        yuanxu-json-schema-node-value
        yuanxu-json-schema-node-metadata
        yuanxu-json-schema-node-record
        yuanxu-json-schema-node->alist
        make-yuanxu-json-schema-property
        yuanxu-json-schema-property?
        yuanxu-json-schema-property-name
        yuanxu-json-schema-property-schema
        yuanxu-json-schema-property-required?
        yuanxu-json-schema-property-doc
        yuanxu-json-schema-property-metadata
        yuanxu-json-schema-property-record
        yuanxu-json-schema-property->alist
        make-yuanxu-json-schema-object
        yuanxu-json-schema-object?
        yuanxu-json-schema-object-properties
        yuanxu-json-schema-object-additional-properties
        yuanxu-json-schema-object-pattern-properties
        yuanxu-json-schema-object-metadata
        yuanxu-json-schema-object-record
        yuanxu-json-schema-object->alist
        make-yuanxu-json-schema-pattern-property
        yuanxu-json-schema-pattern-property?
        yuanxu-json-schema-pattern-property-pattern
        yuanxu-json-schema-pattern-property-compiled
        yuanxu-json-schema-pattern-property-schema
        yuanxu-json-schema-pattern-property-record
        yuanxu-json-schema-pattern-property->alist
        make-yuanxu-json-schema-diagnostic
        yuanxu-json-schema-diagnostic?
        yuanxu-json-schema-diagnostic-severity
        yuanxu-json-schema-diagnostic-reason
        yuanxu-json-schema-diagnostic-message
        yuanxu-json-schema-diagnostic-value
        yuanxu-json-schema-diagnostic-metadata
        yuanxu-json-schema-diagnostic-record
        yuanxu-json-schema-diagnostic->alist
        make-yuanxu-json-schema-normalization
        yuanxu-json-schema-normalization?
        yuanxu-json-schema-normalization-schema
        yuanxu-json-schema-normalization-references
        yuanxu-json-schema-normalization-diagnostics
        yuanxu-json-schema-normalization-record
        yuanxu-json-schema-normalization->alist
        +yuanxu-json-schema-supported-keywords+)

;; : [String]
(def +yuanxu-json-schema-supported-keywords+
  '("$schema"
    "$comment"
    "$ref"
    "$defs"
    "title"
    "description"
    "default"
    "examples"
    "format"
    "type"
    "required"
    "properties"
    "additionalProperties"
    "patternProperties"
    "enum"
    "const"
    "anyOf"
    "allOf"
    "oneOf"
    "items"
    "minLength"
    "maxLength"
    "pattern"
    "minimum"
    "maximum"
    "exclusiveMinimum"
    "exclusiveMaximum"
    "minItems"
    "maxItems"
    "minProperties"
    "maxProperties"
    "definitions"))

;; yuanxu-json-schema-node
;;   : (-> Symbol JsonSchemaDatum Alist YuanxuJsonSchemaNode)
;;   | doc m%
;;       Fixed normalized schema node. KIND is an internal tag such as
;;       `object`, `string`, `nullable`, `enum`, or `predicate-fallback`.
;;     %
(defstruct yuanxu-json-schema-node
  (kind value metadata)
  transparent: #t)

;; : (-> Symbol JsonSchemaDatum [Alist] YuanxuJsonSchemaNode)
(def (yuanxu-json-schema-node-record kind value . maybe-metadata)
  (make-yuanxu-json-schema-node
   kind
   value
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; yuanxu-json-schema-property
;;   : (-> Symbol YuanxuJsonSchemaNode Boolean MaybeString Alist YuanxuJsonSchemaProperty)
;;   | doc m%
;;       Object property row after `required` has been merged into per-field
;;       optionality.
;;     %
(defstruct yuanxu-json-schema-property
  (name schema required? doc metadata)
  transparent: #t)

;; : (-> Symbol YuanxuJsonSchemaNode Boolean MaybeString [Alist] YuanxuJsonSchemaProperty)
(def (yuanxu-json-schema-property-record name schema required? doc
                                           . maybe-metadata)
  (make-yuanxu-json-schema-property
   name
   schema
   required?
   doc
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; yuanxu-json-schema-object
;;   : (-> [YuanxuJsonSchemaProperty] JsonSchemaMapValueSchema [YuanxuJsonSchemaPatternProperty] Alist YuanxuJsonSchemaObject)
;;   | doc m%
;;       Object schema payload. Map-value schemas are normalized IR nodes, so
;;       validators can recurse into dynamic object keys without reparsing raw
;;       JSON Schema rows.
;;     %
(defstruct yuanxu-json-schema-object
  (properties additional-properties pattern-properties metadata)
  transparent: #t)

;; : (-> [YuanxuJsonSchemaProperty] JsonSchemaMapValueSchema [YuanxuJsonSchemaPatternProperty] [Alist] YuanxuJsonSchemaObject)
(def (yuanxu-json-schema-object-record properties additional-properties
                                         pattern-properties . maybe-metadata)
  (make-yuanxu-json-schema-object
   properties
   additional-properties
   pattern-properties
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; yuanxu-json-schema-pattern-property
;;   : (-> String CompiledPattern YuanxuJsonSchemaNode YuanxuJsonSchemaPatternProperty)
;;   | doc m%
;;       Dynamic object key row for `patternProperties`. The compiled pattern
;;       is runtime-only; public projections keep the source pattern string and
;;       normalized child schema.
;;     %
(defstruct yuanxu-json-schema-pattern-property
  (pattern compiled schema)
  transparent: #t)

;; : (-> String Object YuanxuJsonSchemaNode YuanxuJsonSchemaPatternProperty)
(def (yuanxu-json-schema-pattern-property-record pattern compiled schema)
  (make-yuanxu-json-schema-pattern-property pattern compiled schema))

;; yuanxu-json-schema-diagnostic
;;   : (-> Symbol Symbol String JsonSchemaDatum Alist YuanxuJsonSchemaDiagnostic)
;;   | doc m%
;;       Normalizer/emitter diagnostic row before observability wrapping.
;;     %
(defstruct yuanxu-json-schema-diagnostic
  (severity reason message value metadata)
  transparent: #t)

;; : (-> Symbol Symbol String JsonSchemaDatum [Alist] YuanxuJsonSchemaDiagnostic)
(def (yuanxu-json-schema-diagnostic-record severity reason message value
                                             . maybe-metadata)
  (make-yuanxu-json-schema-diagnostic
   severity
   reason
   message
   value
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; yuanxu-json-schema-normalization
;;   : (-> YuanxuJsonSchemaNode Alist [YuanxuJsonSchemaDiagnostic] YuanxuJsonSchemaNormalization)
;;   | doc m%
;;       Pure normalization receipt. Final public receipts are built by
;;       json-schema-receipt.ss.
;;     %
(defstruct yuanxu-json-schema-normalization
  (schema references diagnostics)
  transparent: #t)

;; : (-> YuanxuJsonSchemaNode Alist [YuanxuJsonSchemaDiagnostic] YuanxuJsonSchemaNormalization)
(def (yuanxu-json-schema-normalization-record schema references diagnostics)
  (make-yuanxu-json-schema-normalization schema references diagnostics))

;; : (-> JsonSchemaDatum JsonSchemaDatum)
(def (yuanxu-json-schema-project value)
  (cond
   ((yuanxu-json-schema-node? value)
    (yuanxu-json-schema-node->alist value))
   ((yuanxu-json-schema-property? value)
    (yuanxu-json-schema-property->alist value))
   ((yuanxu-json-schema-object? value)
    (yuanxu-json-schema-object->alist value))
   ((yuanxu-json-schema-pattern-property? value)
    (yuanxu-json-schema-pattern-property->alist value))
   ((yuanxu-json-schema-diagnostic? value)
    (yuanxu-json-schema-diagnostic->alist value))
   ((pair? value)
    (cons (yuanxu-json-schema-project (car value))
          (yuanxu-json-schema-project (cdr value))))
   (else value)))

;; : (-> YuanxuJsonSchemaNode Alist)
(def (yuanxu-json-schema-node->alist node)
  (list
   (cons 'kind (yuanxu-json-schema-node-kind node))
   (cons 'value
         (yuanxu-json-schema-project
          (yuanxu-json-schema-node-value node)))
   (cons 'metadata (yuanxu-json-schema-node-metadata node))))

;; : (-> YuanxuJsonSchemaProperty Alist)
(def (yuanxu-json-schema-property->alist property)
  (list
   (cons 'name (yuanxu-json-schema-property-name property))
   (cons 'schema
         (yuanxu-json-schema-node->alist
          (yuanxu-json-schema-property-schema property)))
   (cons 'required? (yuanxu-json-schema-property-required? property))
   (cons 'doc (yuanxu-json-schema-property-doc property))
   (cons 'metadata (yuanxu-json-schema-property-metadata property))))

;; : (-> YuanxuJsonSchemaPatternProperty Alist)
(def (yuanxu-json-schema-pattern-property->alist pattern-property)
  (cons
   (yuanxu-json-schema-pattern-property-pattern pattern-property)
   (yuanxu-json-schema-node->alist
    (yuanxu-json-schema-pattern-property-schema pattern-property))))

;; : (forall (v) (-> v [(Pair Symbol Object)]))
;; : (-> YuanxuJsonSchemaObject Alist)
(def (yuanxu-json-schema-object->alist object)
  (list
   (cons 'properties
         (map yuanxu-json-schema-property->alist
              (yuanxu-json-schema-object-properties object)))
   (cons 'additional-properties
         (yuanxu-json-schema-project
          (yuanxu-json-schema-object-additional-properties object)))
   (cons 'pattern-properties
         (yuanxu-json-schema-project
          (yuanxu-json-schema-object-pattern-properties object)))
   (cons 'metadata (yuanxu-json-schema-object-metadata object))))

;; : (-> YuanxuJsonSchemaDiagnostic Alist)
(def (yuanxu-json-schema-diagnostic->alist diagnostic)
  (list
   (cons 'severity
         (yuanxu-json-schema-diagnostic-severity diagnostic))
   (cons 'reason
         (yuanxu-json-schema-diagnostic-reason diagnostic))
   (cons 'message
         (yuanxu-json-schema-diagnostic-message diagnostic))
   (cons 'value
         (yuanxu-json-schema-diagnostic-value diagnostic))
   (cons 'metadata
         (yuanxu-json-schema-diagnostic-metadata diagnostic))))

;; : (forall (v) (-> v [(Pair Symbol Object)]))
;; : (-> YuanxuJsonSchemaNormalization Alist)
(def (yuanxu-json-schema-normalization->alist normalization)
  (list
   (cons 'schema
         (yuanxu-json-schema-node->alist
          (yuanxu-json-schema-normalization-schema normalization)))
   (cons 'references
         (map (lambda (entry)
                (cons (car entry)
                      (yuanxu-json-schema-node->alist (cdr entry))))
              (yuanxu-json-schema-normalization-references normalization)))
   (cons 'diagnostics
         (map yuanxu-json-schema-diagnostic->alist
              (yuanxu-json-schema-normalization-diagnostics normalization)))))
