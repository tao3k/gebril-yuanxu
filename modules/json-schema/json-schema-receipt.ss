;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: public receipt for JSON Schema to Yuanxu contract generation.

(import (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-object-contract->alist)
        (only-in :yuanxu/object-types/facts
                 yuanxu-type-fact-contract->alist
                 yuanxu-lean-fact-contract->alist
                 yuanxu-object-contract->type-facts
                 yuanxu-object-contract->lean-fact-contracts)
        (only-in :yuanxu/observability/objects
                 yuanxu-observability-diagnostic-record
                 yuanxu-observability-diagnostic-severity
                 yuanxu-observability-diagnostic->alist)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-diagnostic-severity
                 yuanxu-json-schema-diagnostic-reason
                 yuanxu-json-schema-diagnostic-message
                 yuanxu-json-schema-diagnostic-value
                 yuanxu-json-schema-diagnostic->alist
                 yuanxu-json-schema-normalization-schema
                 yuanxu-json-schema-normalization-diagnostics
                 yuanxu-json-schema-normalization->alist)
        (only-in "./functional.ss"
                 yuanxu-contract-any?
                 yuanxu-contract-option
                 yuanxu-contract-project-list)
        (only-in "./json-schema-normalize.ss"
                 yuanxu-json-schema-normalize)
        (only-in "./json-schema-emit.ss"
                 yuanxu-json-schema-node->object-type-contract))

(export make-yuanxu-json-schema-contract-artifact
        yuanxu-json-schema-contract-artifact?
        yuanxu-json-schema-contract-artifact-kind
        yuanxu-json-schema-contract-artifact-schema
        yuanxu-json-schema-contract-artifact-source-ref
        yuanxu-json-schema-contract-artifact-normalization
        yuanxu-json-schema-contract-artifact-object-contract
        yuanxu-json-schema-contract-artifact-diagnostics
        yuanxu-json-schema-contract-artifact-type-facts
        yuanxu-json-schema-contract-artifact-lean-fact-contracts
        yuanxu-json-schema-contract-artifact-runtime-executed
        yuanxu-json-schema-contract-artifact-valid?
        yuanxu-json-schema-contract-artifact->alist
        yuanxu-json-schema-diagnostic->observability
        yuanxu-json-schema->contract-artifact)

;; yuanxu-json-schema-contract-artifact
;;   : (-> Symbol String SourceRef YuanxuJsonSchemaNormalization YuanxuObjectTypeContract [Diagnostic] [TypeFact] [LeanFact] Boolean Artifact)
;;   | doc m%
;;       Fixed public receipt for JSON Schema contract generation. The generated
;;       object contract is still Scheme data; external payloads use ->alist.
;;     %
(defstruct yuanxu-json-schema-contract-artifact
  (kind
   schema
   source-ref
   normalization
   object-contract
   diagnostics
   type-facts
   lean-fact-contracts
   runtime-executed)
  transparent: #t)

;; : (-> Alist Symbol Value)
(def (yuanxu-json-schema-option options key default-value)
  (yuanxu-contract-option options key default-value))

;; : (-> YuanxuJsonSchemaDiagnostic YuanxuObservabilityDiagnostic)
(def (yuanxu-json-schema-diagnostic->observability diagnostic)
  (yuanxu-observability-diagnostic-record
   (yuanxu-json-schema-diagnostic-severity diagnostic)
   'contract
   'json-schema-contract
   #f
   #f
   (yuanxu-json-schema-diagnostic-reason diagnostic)
   (yuanxu-json-schema-diagnostic-message diagnostic)
   'contract
   (list
    (cons 'value (yuanxu-json-schema-diagnostic-value diagnostic))
    (cons 'diagnostic
          (yuanxu-json-schema-diagnostic->alist diagnostic)))))

;; : (-> YuanxuObservabilityDiagnostic Boolean)
(def (yuanxu-json-schema-diagnostic-fatal? diagnostic)
  (let (severity (yuanxu-observability-diagnostic-severity diagnostic))
    (or (eq? severity 'error)
        (eq? severity 'fatal))))

;; : (-> YuanxuJsonSchemaContractArtifact Boolean)
(def (yuanxu-json-schema-contract-artifact-valid? artifact)
  (and (yuanxu-json-schema-contract-artifact? artifact)
       (not
        (yuanxu-contract-any?
         yuanxu-json-schema-diagnostic-fatal?
         (yuanxu-json-schema-contract-artifact-diagnostics artifact)))))

;; : (-> YuanxuJsonSchemaContractArtifact Alist)
(def (yuanxu-json-schema-contract-artifact->alist artifact)
  (list
   (cons 'kind
         (yuanxu-json-schema-contract-artifact-kind artifact))
   (cons 'schema
         (yuanxu-json-schema-contract-artifact-schema artifact))
   (cons 'source-ref
         (yuanxu-json-schema-contract-artifact-source-ref artifact))
   (cons 'valid?
         (yuanxu-json-schema-contract-artifact-valid? artifact))
   (cons 'normalization
         (yuanxu-json-schema-normalization->alist
          (yuanxu-json-schema-contract-artifact-normalization artifact)))
   (cons 'object-contract
         (yuanxu-object-contract->alist
          (yuanxu-json-schema-contract-artifact-object-contract artifact)))
   (cons 'diagnostics
         (yuanxu-contract-project-list
          yuanxu-observability-diagnostic->alist
          (yuanxu-json-schema-contract-artifact-diagnostics artifact)))
   (cons 'diagnostic-count
         (length
          (yuanxu-json-schema-contract-artifact-diagnostics artifact)))
   (cons 'type-facts
         (yuanxu-contract-project-list
          yuanxu-type-fact-contract->alist
          (yuanxu-json-schema-contract-artifact-type-facts artifact)))
   (cons 'lean-fact-contracts
         (yuanxu-contract-project-list
          yuanxu-lean-fact-contract->alist
          (yuanxu-json-schema-contract-artifact-lean-fact-contracts artifact)))
   (cons 'runtime-executed
         (yuanxu-json-schema-contract-artifact-runtime-executed artifact))))

;; : (-> JsonLikeSchema [Alist] YuanxuJsonSchemaContractArtifact)
(def (yuanxu-json-schema->contract-artifact schema . maybe-options)
  (let* ((options (if (null? maybe-options) '() (car maybe-options)))
         (source-ref
          (yuanxu-json-schema-option options 'source-ref 'json-schema))
         (owner
          (yuanxu-json-schema-option options 'owner 'contract))
         (object-kind
          (yuanxu-json-schema-option
           options
           'object-kind
           'YuanxuJsonSchemaObject))
         (object-key
          (yuanxu-json-schema-option
           options
           'object-key
           'json-schema/root))
         (normalization
          (yuanxu-json-schema-normalize schema))
         (object-contract
          (yuanxu-json-schema-node->object-type-contract
           (yuanxu-json-schema-normalization-schema normalization)
           owner
           object-kind
           object-key))
         (diagnostics
          (yuanxu-contract-project-list
           yuanxu-json-schema-diagnostic->observability
           (yuanxu-json-schema-normalization-diagnostics normalization)))
         (type-facts
          (yuanxu-object-contract->type-facts object-contract))
         (lean-fact-contracts
          (yuanxu-object-contract->lean-fact-contracts object-contract)))
    (make-yuanxu-json-schema-contract-artifact
     'json-schema-contract-artifact
     "yuanxu-json-schema-contract-artifact/v1"
     source-ref
     normalization
     object-contract
     diagnostics
     type-facts
     lean-fact-contracts
     #f)))
