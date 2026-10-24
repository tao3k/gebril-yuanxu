;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: field, contribution, and transformer contracts for module objects.

(import :gerbil/core
        (only-in :clan/poo/object
                 .cc
                 .mix
                 .o
                 .ref
                 .slot?
                 object?
                 make-object
                 $constant-slot-spec
                 $computed-slot-spec)
        (only-in :clan/poo/mop
                 .defgeneric Any Bool Object Type element? raise-type-error)
        (only-in :clan/poo/type List String Symbol)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-type)
        :yuanxu/graph/interface)

(export yuanxu-module-object-kind
        yuanxu-module-field-contract-kind
        yuanxu-module-field-contribution-kind
        yuanxu-module-transformer-contract-kind
        yuanxu-module-field-resolution-result-kind
        yuanxu-module-objects-root-identity
        yuanxu-module-object-kind?
        yuanxu-module-alist?
        YuanxuModuleAnyType
        YuanxuModuleListType
        YuanxuModuleMapType
        YuanxuModuleAlistType
        YuanxuModuleSymbolType
        YuanxuModuleStringType
        YuanxuModuleBooleanType
        YuanxuModuleObjectType
        YuanxuModuleNodeType
        yuanxu-module-list-type
        yuanxu-module-value-type?
        yuanxu-module-value-type-kind
        yuanxu-module-value-type-accepts?
        yuanxu-module-field-contract
        yuanxu-module-field-contract?
        yuanxu-module-field-contract-identity
        yuanxu-module-field-contract-value-type
        yuanxu-module-field-contract-merge
        yuanxu-module-field-contract-default
        yuanxu-module-field-contract-metadata
        yuanxu-module-field-contract-accepts?
        yuanxu-module-field-contract-with-merge
        yuanxu-module-field-contribution-prototype
        yuanxu-module-field-contribution
        yuanxu-module-field-contribution?
        yuanxu-module-field-contribution-target
        yuanxu-module-field-contribution-field
        yuanxu-module-field-contribution-value
        yuanxu-module-field-contribution-field-contract?
        yuanxu-module-field-contribution-field-value-type
        yuanxu-module-field-contribution-field-identity
        yuanxu-module-field-contribution-merge
        yuanxu-module-field-contribution-valid?
        yuanxu-module-field-contribution-operation
        yuanxu-module-field-contribution->extension
        yuanxu-module-field-contributions->extensions
        yuanxu-module-transformer-contract
        yuanxu-module-transformer-contract?
        yuanxu-module-transformer-contract-identity
        yuanxu-module-transformer-contract-merge
        yuanxu-module-transformer-contract-input-type
        yuanxu-module-transformer-contract-argument-type
        yuanxu-module-transformer-contract-output-type
        yuanxu-module-transformer-contract-idempotent?
        yuanxu-module-transformer-contract-identity-key
        yuanxu-module-transformer-contract-metadata
        yuanxu-module-transformer-list-append-contract
        yuanxu-module-transformer-list-remove-contract
        yuanxu-module-transformer-map-set-contract
        yuanxu-module-transformer-type-compatible?
        yuanxu-module-transformer-diagnostic
        yuanxu-module-transformer-contract-diagnostics
        yuanxu-module-transformer-contract-valid?
        yuanxu-module-transformer-field-contribution)

;; | PooModuleObjectKindId = String
(def yuanxu-module-object-kind "yuanxu.modules.object.v1")
;; : PooModuleFieldContractKindId
;; | PooModuleFieldContractKindId = String
(def yuanxu-module-field-contract-kind "yuanxu.modules.field-contract.v1")
;; : PooModuleFieldContributionKindId
;; | PooModuleFieldContributionKindId = String
(def yuanxu-module-field-contribution-kind "yuanxu.modules.field-contribution.v1")
;; : PooModuleTransformerContractKindId
;; | PooModuleTransformerContractKindId = String
(def yuanxu-module-transformer-contract-kind "yuanxu.modules.transformer-contract.v1")
;; : PooModuleFieldResolutionResultKindId
;; | PooModuleFieldResolutionResultKindId = String
(def yuanxu-module-field-resolution-result-kind "yuanxu.modules.field-resolution-result.v1")
;; : PooModuleObjectsRootIdentity
;; | PooModuleObjectsRootIdentity = Symbol
(def yuanxu-module-objects-root-identity 'objects)

;; : (-> PooModuleValueCandidate PooModuleKindId Boolean)
(def (yuanxu-module-object-kind? value kind)
  (and (object? value) (equal? (.ref value 'kind) kind)))

;; | PooModuleAlistCandidate = (U Null Pair)
;; : (-> PooModuleAlistCandidate Boolean)
(def (yuanxu-module-alist? value)
  (cond ((null? value) #t)
        ((and (pair? value) (pair? (car value)))
         (yuanxu-module-alist? (cdr value)))
        (else #f)))

;;; Module field types are native gerbil-poo Type descriptors.  The symbol in
;;; `module-value-kind` is a report-only projection; native Type owns semantic
;;; dispatch and admission.
(def (yuanxu-module-value-type base-type kind)
  (.cc base-type
       'module-value-kind kind
       'sexp kind))

(def YuanxuModuleAnyType
  (yuanxu-module-value-type Any 'Any))
(def (yuanxu-module-list-type element-type)
  (yuanxu-module-value-type (List element-type) 'List))
(def YuanxuModuleListType
  (yuanxu-module-list-type Any))
(def YuanxuModuleMapType
  (yuanxu-module-value-type
   (yuanxu-predicate-type 'YuanxuModuleMap yuanxu-module-alist?)
   'Map))
(def YuanxuModuleAlistType
  (yuanxu-module-value-type
   (yuanxu-predicate-type 'YuanxuModuleAlist yuanxu-module-alist?)
   'Alist))
(def YuanxuModuleSymbolType
  (yuanxu-module-value-type Symbol 'Symbol))
(def YuanxuModuleStringType
  (yuanxu-module-value-type String 'String))
(def YuanxuModuleBooleanType
  (yuanxu-module-value-type Bool 'Boolean))
(def YuanxuModuleObjectType
  (yuanxu-module-value-type Object 'Object))
(def YuanxuModuleNodeType
  (yuanxu-module-value-type
   (yuanxu-predicate-type 'YuanxuModuleNode
                            yuanxu-graph?)
   'Node))

(def (yuanxu-module-value-type? value-type)
  (and (element? Type value-type)
       (.slot? value-type 'module-value-kind)
       (symbol? (.ref value-type 'module-value-kind))))

(def (yuanxu-module-value-type-kind value-type)
  (unless (yuanxu-module-value-type? value-type)
    (raise-type-error Type value-type))
  (.ref value-type 'module-value-kind))

(def (yuanxu-module-value-type-accepts? value-type value)
  (and (yuanxu-module-value-type? value-type)
       (element? value-type value)))

;;; Field contracts translate object-level C4 inheritance into merge operations
;;; without hardcoding backend-specific fields in the module system.
;; : (-> Symbol Symbol Symbol PooModuleFieldDefault PooModuleFieldMetadata PooModuleFieldContract)
(def (yuanxu-module-field-contract identity value-type merge default metadata)
  (unless (yuanxu-module-value-type? value-type)
    (raise-type-error Type value-type))
  (let ((identity-value identity)
        (value-type-value value-type)
        (merge-value merge)
        (default-value default)
        (metadata-value metadata))
    (.o kind: yuanxu-module-field-contract-kind
        identity: identity-value
        value-type: value-type-value
        merge: merge-value
        default: default-value
        metadata: metadata-value)))

;; : (-> PooModuleFieldContractCandidate Boolean)
(def (yuanxu-module-field-contract? value)
  (yuanxu-module-object-kind? value yuanxu-module-field-contract-kind))

;; : (-> PooModuleFieldContract Symbol)
(def (yuanxu-module-field-contract-identity field) (.ref field 'identity))
;; : (-> PooModuleFieldContract Symbol)
(def (yuanxu-module-field-contract-value-type field) (.ref field 'value-type))
;; : (-> PooModuleFieldContract Symbol)
(def (yuanxu-module-field-contract-merge field) (.ref field 'merge))
;; : (-> PooModuleFieldContract PooModuleFieldDefault)
(def (yuanxu-module-field-contract-default field) (.ref field 'default))
;; : (-> PooModuleFieldContract PooModuleFieldMetadata)
(def (yuanxu-module-field-contract-metadata field) (.ref field 'metadata))

;;; Value-kind checks are intentionally shallow; object-specific transformer
;;; contracts can refine this before an extension operation is projected.
;; : (-> PooModuleFieldContract PooModuleFieldValueCandidate Boolean)
(def (yuanxu-module-field-contract-accepts? field value)
  (yuanxu-module-value-type-accepts?
   (yuanxu-module-field-contract-value-type field)
   value))

;; : (-> PooModuleFieldContract Symbol PooModuleFieldContract)
(def (yuanxu-module-field-contract-with-merge field merge)
  (yuanxu-module-field-contract
   (yuanxu-module-field-contract-identity field)
   (yuanxu-module-field-contract-value-type field)
   merge
   (yuanxu-module-field-contract-default field)
   (yuanxu-module-field-contract-metadata field)))

;;; The contribution prototype owns derived extension behavior.  Concrete
;;; contributions refine this native POO value with constant defaults; no
;;; positional record or compatibility representation participates in dispatch.
(def yuanxu-module-field-contribution-prototype
  (.o (:: self)
      kind: yuanxu-module-field-contribution-kind
      (.operation
       (yuanxu-module-field-operation
        (.ref self 'field-identity)
        (.ref self 'field-merge)
        (.ref self 'value)))))

;;; Field contributions are object-aware extension requests: the field decides
;;; merge behavior while the contribution carries target and value.
;; : (-> Symbol PooModuleFieldContract PooModuleFieldValue PooModuleFieldContribution)
(def (yuanxu-module-field-contribution target field value)
  (let* ((target-value target)
         (field-value field)
         (value-value value)
         (field-contract? (yuanxu-module-field-contract? field-value))
         (field-identity-value
          (if field-contract?
            (yuanxu-module-field-contract-identity field-value)
            field-value))
         (field-merge-value
          (if field-contract?
            (yuanxu-module-field-contract-merge field-value)
            'override))
         (field-value-type-value
          (if field-contract?
            (yuanxu-module-field-contract-value-type field-value)
            YuanxuModuleAnyType)))
    (.mix yuanxu-module-field-contribution-prototype
      defaults: (list
                 (cons 'target target-value)
                 (cons 'field field-value)
                 (cons 'value value-value)
                 (cons 'field-identity field-identity-value)
                 (cons 'field-merge field-merge-value)
                 (cons 'field-value-type field-value-type-value)
                 (cons 'field-contract? field-contract?)))))

;; : (-> PooModuleFieldContributionCandidate Boolean)
(def (yuanxu-module-field-contribution? value)
  (yuanxu-module-object-kind? value yuanxu-module-field-contribution-kind))

;;; Boundary: module field contribution target is the policy-visible edge for
;;; module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution Symbol)
(def (yuanxu-module-field-contribution-target contribution)
  (.ref contribution 'target))
;;; Boundary: module field contribution field is the policy-visible edge for
;;; module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution PooModuleFieldContract)
(def (yuanxu-module-field-contribution-field contribution)
  (.ref contribution 'field))
;;; Boundary: module field contribution value is the policy-visible edge for
;;; module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution PooModuleFieldValue)
(def (yuanxu-module-field-contribution-value contribution)
  (.ref contribution 'value))
;;; Boundary: module field contribution field contract predicate is the policy-
;;; visible edge for module-system, object, core behavior, keeping validation,
;;; lookup, or projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution Boolean)
(def (yuanxu-module-field-contribution-field-contract? contribution)
  (.ref contribution 'field-contract?))
;;; Boundary: module field contribution field value kind is the policy-visible
;;; edge for module-system, object, core behavior, keeping validation, lookup,
;;; or projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution Symbol)
(def (yuanxu-module-field-contribution-field-value-type contribution)
  (.ref contribution 'field-value-type))

;;; Boundary: module field contribution field identity is the policy-visible
;;; edge for module-system, object, core behavior, keeping validation, lookup,
;;; or projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution Symbol)
(def (yuanxu-module-field-contribution-field-identity contribution)
  (.ref contribution 'field-identity))

;;; Boundary: module field contribution merge is the policy-visible edge for
;;; module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution Symbol)
(def (yuanxu-module-field-contribution-merge contribution)
  (.ref contribution 'field-merge))

;; : (-> PooModuleFieldContribution Boolean)
(def (yuanxu-module-field-contribution-valid? contribution)
  (or (not (yuanxu-module-field-contribution-field-contract? contribution))
      (yuanxu-module-value-type-accepts?
       (yuanxu-module-field-contribution-field-value-type contribution)
       (yuanxu-module-field-contribution-value contribution))))

;;; Field merge names are interpreted once behind the prototype method.  The
;;; contribution-to-extension path dispatches through native POO slots.
;; : (-> Symbol Symbol PooModuleFieldValue PooGraphOperation)
(def (yuanxu-module-field-operation field-identity merge value)
  (cond
   ((eq? merge 'override)
    (yuanxu-graph-slot-override field-identity value))
   ((eq? merge 'append)
    (yuanxu-graph-slot-append field-identity value))
   ((eq? merge 'prepend)
    (yuanxu-graph-slot-prepend field-identity value))
   ((eq? merge 'remove)
    (yuanxu-graph-slot-remove field-identity value))
   ((eq? merge 'node-extend)
    (yuanxu-graph-node-extend value))
   ((eq? merge 'node-remove)
    (yuanxu-graph-node-remove value))
   (else
    (yuanxu-graph-slot-override field-identity value))))

;;; Native generic dispatch lets refined contribution prototypes replace the
;;; projection without extending this owner with another representation case.
;; : (-> PooModuleFieldContribution PooGraphOperation)
(.defgeneric (yuanxu-module-field-contribution-operation contribution)
  slot: .operation)

;;; Boundary: module field contribution to extension is the policy-visible edge
;;; for module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> PooModuleFieldContribution PooGraphContribution)
(def (yuanxu-module-field-contribution->extension contribution)
  (if (yuanxu-module-field-contribution-valid? contribution)
    (yuanxu-graph-contribution
     (yuanxu-module-field-contribution-target contribution)
     (list (yuanxu-module-field-contribution-operation contribution)))
      (error "Yuanxu module field contribution violates its POO contract"
             contribution)))

;;; Field contribution projection is a map because validation happens at each
;;; contribution boundary before the generic extension graph sees operations.
;; : (-> [PooModuleFieldContribution] [PooGraphContribution])
(def (yuanxu-module-field-contributions->extensions contributions)
  (map yuanxu-module-field-contribution->extension contributions))

;;; Transformer contracts are object-owned wrappers around standard
;;; list/map-shaped operations. They validate user or agent repair payloads
;;; before those payloads become ordinary field contributions.
;; : (forall (m) (-> Symbol Symbol Symbol Symbol Symbol Boolean MaybeSymbol m PooModuleTransformerContract))
;; : (-> Symbol Symbol Symbol Symbol Symbol Boolean MaybeSymbol Alist PooModuleTransformerContract)
(def (yuanxu-module-transformer-contract identity
                                           merge
                                           input-type
                                           argument-type
                                           output-type
                                           idempotent?
                                           identity-key
                                           metadata)
  (for-each
   (lambda (value-type)
     (unless (yuanxu-module-value-type? value-type)
       (raise-type-error Type value-type)))
   (list input-type argument-type output-type))
  (let ((identity-value identity)
        (merge-value merge)
        (input-type-value input-type)
        (argument-type-value argument-type)
        (output-type-value output-type)
        (idempotent-value idempotent?)
        (identity-key-value identity-key)
        (metadata-value metadata))
    (.o kind: yuanxu-module-transformer-contract-kind
        identity: identity-value
        merge: merge-value
        input-type: input-type-value
        argument-type: argument-type-value
        output-type: output-type-value
        idempotent?: idempotent-value
        identity-key: identity-key-value
        metadata: metadata-value)))

;; : (-> PooModuleTransformerContractCandidate Boolean)
(def (yuanxu-module-transformer-contract? value)
  (yuanxu-module-object-kind? value yuanxu-module-transformer-contract-kind))

;; : (-> PooModuleTransformerContract Symbol)
(def (yuanxu-module-transformer-contract-identity transformer)
  (.ref transformer 'identity))
;; : (-> PooModuleTransformerContract Symbol)
(def (yuanxu-module-transformer-contract-merge transformer)
  (.ref transformer 'merge))
;; : (-> PooModuleTransformerContract Symbol)
(def (yuanxu-module-transformer-contract-input-type transformer)
  (.ref transformer 'input-type))
;; : (-> PooModuleTransformerContract Symbol)
(def (yuanxu-module-transformer-contract-argument-type transformer)
  (.ref transformer 'argument-type))
;; : (-> PooModuleTransformerContract Symbol)
(def (yuanxu-module-transformer-contract-output-type transformer)
  (.ref transformer 'output-type))
;; : (-> PooModuleTransformerContract Boolean)
(def (yuanxu-module-transformer-contract-idempotent? transformer)
  (.ref transformer 'idempotent?))
;; : (-> PooModuleTransformerContract MaybeSymbol)
(def (yuanxu-module-transformer-contract-identity-key transformer)
  (.ref transformer 'identity-key))
;; : (-> PooModuleTransformerContract Alist)
(def (yuanxu-module-transformer-contract-metadata transformer)
  (.ref transformer 'metadata))

;; : PooModuleTransformerContract
(def yuanxu-module-transformer-list-append-contract
  (yuanxu-module-transformer-contract
   'list.append
   'append
   YuanxuModuleListType
   YuanxuModuleListType
   YuanxuModuleListType
   #t
   #f
   '((scope . object-core) (standard-library-shape . list.append))))

;; : PooModuleTransformerContract
(def yuanxu-module-transformer-list-remove-contract
  (yuanxu-module-transformer-contract
   'list.remove
   'remove
   YuanxuModuleListType
   YuanxuModuleListType
   YuanxuModuleListType
   #t
   #f
   '((scope . object-core) (standard-library-shape . list.remove))))

;; : PooModuleTransformerContract
(def yuanxu-module-transformer-map-set-contract
  (yuanxu-module-transformer-contract
   'map.set
   'override
   YuanxuModuleMapType
   YuanxuModuleMapType
   YuanxuModuleMapType
   #t
   #f
   '((scope . object-core) (standard-library-shape . map.set))))

;; : (-> Symbol Symbol Boolean)
(def (yuanxu-module-transformer-type-compatible? expected actual)
  (or (eq? expected YuanxuModuleAnyType)
      (eq? actual YuanxuModuleAnyType)
      (eq? expected actual)
      (and (eq? expected YuanxuModuleMapType)
           (eq? actual YuanxuModuleAlistType))
      (and (eq? expected YuanxuModuleAlistType)
           (eq? actual YuanxuModuleMapType))))

;; : (-> Symbol PooModuleTransformerContract String)
(def (yuanxu-module-transformer-diagnostic code transformer)
  (string-append
   "transformer:"
   (symbol->string (yuanxu-module-transformer-contract-identity transformer))
   ":"
   (symbol->string code)))

;;; Boundary: module transformer contract diagnostics is the policy-visible
;;; edge for module-system, object, core behavior, keeping validation, lookup,
;;; or projection responsibilities centralized for callers.
;; : (-> PooModuleTransformerContract PooModuleFieldContract PooModuleFieldValue [String])
(def (yuanxu-module-transformer-contract-diagnostics transformer field value)
  (append
   (if (yuanxu-module-transformer-type-compatible?
        (yuanxu-module-transformer-contract-input-type transformer)
        (yuanxu-module-field-contract-value-type field))
     '()
     (list (yuanxu-module-transformer-diagnostic
            'field-kind-mismatch
            transformer)))
   (if (yuanxu-module-value-type-accepts?
        (yuanxu-module-transformer-contract-argument-type transformer)
        value)
     '()
     (list (yuanxu-module-transformer-diagnostic
            'argument-kind-mismatch
            transformer)))))

;; : (-> PooModuleTransformerContract PooModuleFieldContract PooModuleFieldValue Boolean)
(def (yuanxu-module-transformer-contract-valid? transformer field value)
  (null? (yuanxu-module-transformer-contract-diagnostics
          transformer
          field
          value)))

;;; Boundary: module transformer field contribution is the policy-visible edge
;;; for module-system, object, core behavior, keeping validation, lookup, or
;;; projection responsibilities centralized for callers.
;; : (-> Symbol PooModuleFieldContract PooModuleTransformerContract PooModuleFieldValue PooModuleFieldContribution)
(def (yuanxu-module-transformer-field-contribution target field transformer value)
  (if (yuanxu-module-transformer-contract-valid? transformer field value)
    (yuanxu-module-field-contribution
     target
     (yuanxu-module-field-contract-with-merge
      field
      (yuanxu-module-transformer-contract-merge transformer))
     value)
    (error "Yuanxu module transformer violates its POO contract"
           (yuanxu-module-transformer-contract-diagnostics
            transformer
            field
            value))))
