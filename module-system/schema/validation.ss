;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Native module-schema admission. Gerbil POO owns Type and C4 semantics;
;;; this module checks only the field and catalog contracts built on them.

(import :gerbil/core
        (only-in :clan/poo/object .o .ref object? compute-precedence-list!)
        (only-in :std/list/list foldl)
        :yuanxu/module-system/schema/interface)

(export yuanxu-module-object-validation-kind
        yuanxu-module-object-validation-schema
        yuanxu-module-field-contract-validation-kind
        yuanxu-module-field-contract-validation
        yuanxu-module-field-contract-validation-valid?
        yuanxu-module-object-inheritance-chain
        yuanxu-module-object-validation
        yuanxu-module-object-validation?
        yuanxu-module-object-validation-valid?
        yuanxu-module-object-validation-diagnostics
        yuanxu-module-objects-validation
        yuanxu-module-objects-validation-summary
        yuanxu-require-module-object-validation!
        yuanxu-require-module-objects-validation!)

(def yuanxu-module-object-validation-kind "core.module-schema.validation")
(def yuanxu-module-object-validation-schema
  "core.module-schema.validation/v1")
(def yuanxu-module-field-contract-validation-kind
  "core.module-schema.field-validation")

(def +module-schema-merge-kinds+
  '(override append prepend remove node-extend node-remove))

(def (module-schema-metadata? value)
  (and (list? value) (andmap pair? value)))

(def (module-schema-diagnostic code subject evidence)
  (let ((diagnostic-code code)
        (diagnostic-subject subject)
        (diagnostic-evidence evidence))
    (.o code: diagnostic-code
        subject: diagnostic-subject
        evidence: diagnostic-evidence)))

(def (module-schema-merge-type-compatible? merge type)
  (let (type-kind (and (yuanxu-module-value-type? type)
                      (yuanxu-module-value-type-kind type)))
    (cond
     ((eq? merge 'node-extend) (eq? type-kind 'Node))
     ((eq? merge 'node-remove) (eq? type-kind 'Symbol))
     (else #t))))

(def (module-schema-field-diagnostics field)
  (let* ((identity (yuanxu-module-field-contract-identity field))
         (type (yuanxu-module-field-contract-value-type field))
         (merge (yuanxu-module-field-contract-merge field))
         (default (yuanxu-module-field-contract-default field))
         (metadata (yuanxu-module-field-contract-metadata field)))
    (append
     (if (yuanxu-module-value-type? type)
       '()
       (list (module-schema-diagnostic 'invalid-native-type identity type)))
     (if (memq merge +module-schema-merge-kinds+)
       '()
       (list (module-schema-diagnostic 'unsupported-merge identity merge)))
     (if (module-schema-merge-type-compatible? merge type)
       '()
       (list (module-schema-diagnostic 'merge-type-incompatible
                                       identity merge)))
     (if (module-schema-metadata? metadata)
       '()
       (list (module-schema-diagnostic 'metadata-not-association-list
                                       identity metadata)))
     (if (or (not default)
             (yuanxu-module-value-type-accepts? type default))
       '()
       (list (module-schema-diagnostic 'default-not-in-native-type
                                       identity default))))))

(def (yuanxu-module-field-contract-validation schema-object field-contract)
  (let* ((type (yuanxu-module-field-contract-value-type field-contract))
         (field-diagnostics (module-schema-field-diagnostics field-contract)))
    (.o kind: yuanxu-module-field-contract-validation-kind
        schema: yuanxu-module-object-validation-schema
        object: (yuanxu-module-object-identity schema-object)
        field: (yuanxu-module-field-contract-identity field-contract)
        valueKind: (if (yuanxu-module-value-type? type)
                     (yuanxu-module-value-type-kind type)
                     'invalid-native-type)
        merge: (yuanxu-module-field-contract-merge field-contract)
        valid: (null? field-diagnostics)
        diagnostics: field-diagnostics)))

(def (yuanxu-module-field-contract-validation-valid? validation)
  (.ref validation 'valid))

(def (module-schema-field-identities fields)
  (map (lambda (field)
         (and (yuanxu-module-field-contract? field)
              (yuanxu-module-field-contract-identity field)))
       fields))

(def (yuanxu-module-object-inheritance-chain schema-object)
  (map yuanxu-module-object-identity
       (compute-precedence-list! schema-object)))

(def (module-schema-duplicate-identities identities)
  (let ((seen (make-hash-table))
        (duplicates (make-hash-table)))
    (reverse
     (foldl
      (lambda (identity result)
        (cond
         ((hash-key? duplicates identity) result)
         ((hash-key? seen identity)
          (hash-put! duplicates identity #t)
          (cons identity result))
         (else
          (hash-put! seen identity #t)
          result)))
      '()
      identities))))

(def (module-schema-field-provider precedence identity)
  (let loop ((rest precedence))
    (cond
     ((null? rest) #f)
     ((memq identity
            (module-schema-field-identities
             (yuanxu-module-object-fields (car rest))))
      (car rest))
     (else (loop (cdr rest))))))

(def (module-schema-field-origin schema-object precedence field-contract)
  (let* ((identity (yuanxu-module-field-contract-identity field-contract))
         (field-provider (module-schema-field-provider precedence identity)))
    (.o field: identity
        origin: (if (eq? field-provider schema-object) 'direct 'inherited)
        provider: (and field-provider
                       (yuanxu-module-object-identity field-provider)))))

(def (module-schema-validation-phase name valid? count)
  (.o phase: name status: (if valid? 'ok 'invalid) diagnostic-count: count))

(def (module-schema-object-validation/uncached schema-object)
  (let* ((precedence (compute-precedence-list! schema-object))
         (direct-fields (yuanxu-module-object-fields schema-object))
         (malformed-fields
          (apply append
                 (map (lambda (candidate)
                        (filter (lambda (field)
                                  (not (yuanxu-module-field-contract? field)))
                                (yuanxu-module-object-fields candidate)))
                      precedence)))
         (resolved-fields
          (if (null? malformed-fields)
            (yuanxu-module-object-resolved-fields schema-object)
            '()))
         (direct-identities (module-schema-field-identities direct-fields))
         (resolved-identities (module-schema-field-identities resolved-fields))
         (duplicates (module-schema-duplicate-identities resolved-identities))
         (field-validations
          (map (lambda (field)
                 (yuanxu-module-field-contract-validation schema-object field))
               resolved-fields))
         (field-diagnostics
          (apply append
                 (map (lambda (validation) (.ref validation 'diagnostics))
                      field-validations)))
         (object-metadata (yuanxu-module-object-metadata schema-object))
         (local-diagnostics
          (append
           (map (lambda (field)
                  (module-schema-diagnostic
                   'invalid-field-contract
                   (yuanxu-module-object-identity schema-object)
                   field))
                malformed-fields)
           (if (module-schema-metadata? object-metadata)
             '()
             (list (module-schema-diagnostic
                    'object-metadata-not-association-list
                    (yuanxu-module-object-identity schema-object)
                    object-metadata)))
           (if (null? duplicates)
             '()
             (list (module-schema-diagnostic
                    'duplicate-resolved-field
                   (yuanxu-module-object-identity schema-object)
                   duplicates)))))
         (diagnostic-list (append field-diagnostics local-diagnostics)))
    (.o kind: yuanxu-module-object-validation-kind
        schema: yuanxu-module-object-validation-schema
        object: (yuanxu-module-object-identity schema-object)
        inherits: (map yuanxu-module-object-identity
                       (yuanxu-module-object-inherits schema-object))
        inheritance-chain: (yuanxu-module-object-inheritance-chain
                            schema-object)
        inherit-count: (length (yuanxu-module-object-inherits schema-object))
        direct-field-count: (length direct-fields)
        direct-field-identities: direct-identities
        resolved-field-count: (length resolved-fields)
        resolved-field-identities: resolved-identities
        field-origins: (map (lambda (field)
                             (module-schema-field-origin schema-object precedence field))
                           resolved-fields)
        metadata: object-metadata
        fieldContractValidations: field-validations
        validationPhases:
        (list (module-schema-validation-phase 'native-field-contracts
                                              (null? field-diagnostics)
                                              (length field-diagnostics))
              (module-schema-validation-phase 'module-schema
                                              (null? local-diagnostics)
                                              (length local-diagnostics)))
        valid: (null? diagnostic-list)
        diagnostics: diagnostic-list
        checkedSignals:
        '(native-poo-type native-c4-precedence field-merge-kind
          field-default-type field-metadata-shape object-metadata-shape
          resolved-field-identity))))

(def (yuanxu-module-object-validation object)
  (let (cache (yuanxu-module-object-validation-cache object))
    (if (vector-ref cache 0)
      (vector-ref cache 1)
      (let (validation (module-schema-object-validation/uncached object))
        (vector-set! cache 0 #t)
        (vector-set! cache 1 validation)
        validation))))

(def (yuanxu-module-object-validation? value)
  (and (object? value)
       (equal? (.ref value 'kind)
               yuanxu-module-object-validation-kind)
       (equal? (.ref value 'schema)
               yuanxu-module-object-validation-schema)))

(def (yuanxu-module-object-validation-valid? validation)
  (.ref validation 'valid))

(def (yuanxu-module-object-validation-diagnostics validation)
  (.ref validation 'diagnostics))

(def (yuanxu-module-objects-validation objects)
  (map yuanxu-module-object-validation objects))

(def (yuanxu-module-objects-validation-summary validations)
  (let* ((invalid (filter (lambda (validation)
                            (not (yuanxu-module-object-validation-valid?
                                  validation)))
                          validations))
         (identities (map (lambda (validation) (.ref validation 'object))
                          validations))
         (duplicate-object-ids
          (module-schema-duplicate-identities identities)))
    (.o kind: "core.module-schema.catalog-validation"
        schema: yuanxu-module-object-validation-schema
        object-count: (length validations)
        object-identities: identities
        invalid-count: (length invalid)
        invalid-objects:
        (map (lambda (validation) (.ref validation 'object)) invalid)
        duplicate-identities: duplicate-object-ids
        duplicate-count: (length duplicate-object-ids)
        inheritance-counts:
        (map (lambda (validation) (.ref validation 'inherit-count)) validations)
        inheritance-chains:
        (map (lambda (validation) (.ref validation 'inheritance-chain)) validations)
        field-origins:
        (map (lambda (validation) (.ref validation 'field-origins)) validations)
        validation-phases:
        (map (lambda (validation) (.ref validation 'validationPhases)) validations)
        valid: (and (null? invalid) (null? duplicate-object-ids))
        checkedSignals: '(native-poo-catalog-validation)
        descriptor-realized?: #f
        runtime-executed: #f)))

(def (yuanxu-require-module-object-validation! object)
  (let (validation (yuanxu-module-object-validation object))
    (if (yuanxu-module-object-validation-valid? validation)
      object
      (error "module schema validation failed" validation))))

(def (yuanxu-require-module-objects-validation! objects)
  (let (summary
        (yuanxu-module-objects-validation-summary
         (yuanxu-module-objects-validation objects)))
    (if (.ref summary 'valid)
      objects
      (error "module schema catalog validation failed" summary))))
