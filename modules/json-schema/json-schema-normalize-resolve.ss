;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: normalize JSON-like schema values into Yuanxu JSON Schema IR.
;;; Invariant: this module performs pure import-boundary normalization only.
;;; It does not fetch schemas, execute validators, or emit runtime payloads.

(import (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-node?
                 yuanxu-json-schema-node-kind
                 yuanxu-json-schema-node-value
                 yuanxu-json-schema-node-metadata
                 yuanxu-json-schema-node-record
                 yuanxu-json-schema-object?
                 yuanxu-json-schema-object-properties
                 yuanxu-json-schema-object-additional-properties
                 yuanxu-json-schema-object-pattern-properties
                 yuanxu-json-schema-object-metadata
                 yuanxu-json-schema-object-record
                 yuanxu-json-schema-property-name
                 yuanxu-json-schema-property-schema
                 yuanxu-json-schema-property-required?
                 yuanxu-json-schema-property-doc
                 yuanxu-json-schema-property-metadata
                 yuanxu-json-schema-property-record
                 yuanxu-json-schema-pattern-property-pattern
                 yuanxu-json-schema-pattern-property-compiled
                 yuanxu-json-schema-pattern-property-schema
                 yuanxu-json-schema-pattern-property-record
                 yuanxu-json-schema-diagnostic-record)
        (only-in "./functional.ss"
                 yuanxu-contract-object-ref
                 yuanxu-contract-member?
                 yuanxu-contract-map-pair-with-diagnostics)
        (only-in "./json-schema-normalize-core.ss"
                 yuanxu-json-schema-local-definition-name))

(export #t)

;; yuanxu-json-schema-ref-lookup
;;   : (-> String JsonSchemaReferenceRows MaybeYuanxuJsonSchemaNode)
;;   | result: referenced normalized node or #f
;;   | doc m%
;;       Reference lookup stays on normalized definition rows; external and
;;       missing references are handled by the caller as explicit diagnostics.
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-ref-lookup "User" references)
;;       ;; => maybe-node
;;       ```
;;     %
(def (yuanxu-json-schema-ref-lookup ref-name references)
  (yuanxu-contract-object-ref references ref-name #f))

;; yuanxu-json-schema-resolve-node
;;   : (-> YuanxuJsonSchemaNode JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | doc m%
;;       Resolve references inside a parsed node while carrying the reference
;;       stack used to detect cycles.
;;     %
(def (yuanxu-json-schema-resolve-node node references seen)
  (let (kind (yuanxu-json-schema-node-kind node))
    (cond
     ((eq? kind 'ref)
      (yuanxu-json-schema-resolve-ref node references seen))
     ((eq? kind 'object)
      (yuanxu-json-schema-resolve-object node references seen))
     ((eq? kind 'array)
      (yuanxu-json-schema-resolve-array node references seen))
     ((or (eq? kind 'nullable)
          (eq? kind 'any-of)
          (eq? kind 'all-of)
          (eq? kind 'one-of))
      (yuanxu-json-schema-resolve-sequence node references seen))
     (else
      (cons node '())))))

;; yuanxu-json-schema-resolve-ref
;;   : (-> YuanxuJsonSchemaNode JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | doc m%
;;       Resolve a local definition reference or return a diagnostic fallback
;;       for external, cyclic, and missing references.
;;     %
(def (yuanxu-json-schema-resolve-ref node references seen)
  (let* ((ref (yuanxu-json-schema-node-value node))
         (name (yuanxu-json-schema-local-definition-name ref)))
    ;; Reference resolution must remain bounded: P0 only follows local
    ;; definition names, and the `seen` set prevents recursive schemas from
    ;; creating an unbounded normalized object graph.
    (cond
     ((not name)
      (cons
       (yuanxu-json-schema-node-record
        'predicate-fallback
        'any
        `((ref . ,ref) (fallback . external-reference)))
       (list
        (yuanxu-json-schema-diagnostic-record
         'warning
         'unsupported-reference
         "Only local #/definitions/<name> and #/$defs/<name> references are supported in P0"
         ref
         '((owner . json-schema-normalize))))))
     ((yuanxu-contract-member? name seen)
      (cons
       (yuanxu-json-schema-node-record
        'predicate-fallback
        'any
        `((ref . ,ref) (fallback . cyclic-reference)))
       (list
        (yuanxu-json-schema-diagnostic-record
         'warning
         'cyclic-reference
         "Cyclic JSON Schema references fall back to an opaque predicate"
         ref
         '((owner . json-schema-normalize))))))
     (else
      (let (target (yuanxu-json-schema-ref-lookup name references))
        (if target
          (let (resolved
                (yuanxu-json-schema-resolve-node
                 target
                 references
                 (cons name seen)))
            (cons
             (yuanxu-json-schema-node-record
              (yuanxu-json-schema-node-kind (car resolved))
              (yuanxu-json-schema-node-value (car resolved))
              (cons (cons 'resolved-ref ref)
                    (yuanxu-json-schema-node-metadata (car resolved))))
             (cdr resolved)))
          (cons
           (yuanxu-json-schema-node-record
            'predicate-fallback
            'any
            `((ref . ,ref) (fallback . unresolved-reference)))
           (list
            (yuanxu-json-schema-diagnostic-record
             'warning
             'unresolved-reference
             "Local JSON Schema reference could not be resolved"
             ref
             '((owner . json-schema-normalize)))))))))))

;; yuanxu-json-schema-resolve-object
;;   : (-> YuanxuJsonSchemaNode JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | doc m%
;;       Resolve each property schema inside an object node while preserving the
;;       object's own metadata and additionalProperties value.
;;     %
(def (yuanxu-json-schema-resolve-object node references seen)
  (let* ((object (yuanxu-json-schema-node-value node))
         (resolved
          (yuanxu-json-schema-resolve-properties
           (yuanxu-json-schema-object-properties object)
           references
           seen))
         (resolved-additional
          (yuanxu-json-schema-resolve-additional-properties
           (yuanxu-json-schema-object-additional-properties object)
           references
           seen))
         (resolved-patterns
          (yuanxu-json-schema-resolve-pattern-properties
           (yuanxu-json-schema-object-pattern-properties object)
           references
           seen)))
    (cons
     (yuanxu-json-schema-node-record
      'object
      (yuanxu-json-schema-object-record
       (car resolved)
       (car resolved-additional)
       (car resolved-patterns)
       (yuanxu-json-schema-object-metadata object))
      (yuanxu-json-schema-node-metadata node))
     (append (cdr resolved)
             (cdr resolved-additional)
             (cdr resolved-patterns)))))

;; yuanxu-json-schema-resolve-additional-properties
;;   : (-> JsonSchemaMapValueSchema JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | doc m%
;;       Resolve references inside the normalized additionalProperties schema.
;;     %
(def (yuanxu-json-schema-resolve-additional-properties additional references seen)
  (if (yuanxu-json-schema-node? additional)
    (yuanxu-json-schema-resolve-node additional references seen)
    (cons additional '())))

;; yuanxu-json-schema-resolve-pattern-properties
;;   : (-> [Pair] JsonSchemaReferenceRows [String] JsonSchemaPatternResolveResult)
;;   | doc m%
;;       Resolve references inside every normalized patternProperties value.
;;     %
(def (yuanxu-json-schema-resolve-pattern-properties pattern-properties
                                                     references
                                                     seen)
  (yuanxu-contract-map-pair-with-diagnostics
   (lambda (row)
     (let (resolved
           (yuanxu-json-schema-resolve-node
            (yuanxu-json-schema-pattern-property-schema row)
            references
            seen))
       (cons (yuanxu-json-schema-pattern-property-record
              (yuanxu-json-schema-pattern-property-pattern row)
              (yuanxu-json-schema-pattern-property-compiled row)
              (car resolved))
             (cdr resolved))))
   pattern-properties
   '()))

;; yuanxu-json-schema-resolve-array
;;   : (-> YuanxuJsonSchemaNode JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | result: array node with resolved item schema and diagnostics
;;   | doc m%
;;       Resolve references inside the parsed homogeneous item schema while
;;       preserving array node metadata.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-resolve-array node references seen)
;;       ;; => (resolved-array-node . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-resolve-array node references seen)
  (let* ((value (yuanxu-json-schema-node-value node))
         (resolved
          (if (list? value)
            (let (children
                  (map (lambda (child)
                         (yuanxu-json-schema-resolve-node
                          child
                          references
                          seen))
                       value))
              (cons (map car children)
                    (if (null? children)
                      []
                      (apply append (map cdr children)))))
            (yuanxu-json-schema-resolve-node value references seen))))
    (cons
     (yuanxu-json-schema-node-record
      'array
      (car resolved)
      (yuanxu-json-schema-node-metadata node))
     (cdr resolved))))

;; yuanxu-json-schema-resolve-properties
;;   : (-> [YuanxuJsonSchemaProperty] JsonSchemaReferenceRows [String] JsonSchemaPropertyResolveResult)
;;   | result: resolved properties paired with reference diagnostics
;;   | doc m%
;;       Property resolution walks already-parsed property objects and preserves
;;       property metadata while replacing nested schema nodes with resolved IR.
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-resolve-properties properties references '())
;;       ;; => (properties . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-resolve-properties properties references seen)
  (yuanxu-contract-map-pair-with-diagnostics
   (lambda (property)
     (let (resolved
           (yuanxu-json-schema-resolve-node
            (yuanxu-json-schema-property-schema property)
            references
            seen))
       (cons
        (yuanxu-json-schema-property-record
         (yuanxu-json-schema-property-name property)
         (car resolved)
         (yuanxu-json-schema-property-required? property)
         (yuanxu-json-schema-property-doc property)
         (yuanxu-json-schema-property-metadata property))
        (cdr resolved))))
   properties
   '()))

;; yuanxu-json-schema-resolve-sequence
;;   : (-> YuanxuJsonSchemaNode JsonSchemaReferenceRows [String] JsonSchemaResolveResult)
;;   | result: resolved logical/nullable sequence node with diagnostics
;;   | doc m%
;;       Sequence resolution handles `nullable`, `any-of`, `all-of`, and `one-of`
;;       nodes without changing their public normalized IR shape.
;;       # Examples
;;       ```scheme
;;       (yuanxu-json-schema-resolve-sequence node references '())
;;       ;; => (node . diagnostics)
;;       ```
;;     %
(def (yuanxu-json-schema-resolve-sequence node references seen)
  (let* ((parsed
          (yuanxu-contract-map-pair-with-diagnostics
           (lambda (item)
             (yuanxu-json-schema-resolve-node item references seen))
           (if (list? (yuanxu-json-schema-node-value node))
             (yuanxu-json-schema-node-value node)
             (list (yuanxu-json-schema-node-value node)))
           '()))
         (value (car parsed)))
    (cons
     (yuanxu-json-schema-node-record
      (yuanxu-json-schema-node-kind node)
      (if (eq? (yuanxu-json-schema-node-kind node) 'nullable)
        (car value)
        value)
      (yuanxu-json-schema-node-metadata node))
     (cdr parsed))))
