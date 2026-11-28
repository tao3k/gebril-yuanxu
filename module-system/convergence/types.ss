;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; POO contracts for Yuanxu Design 165: Two-Tier Interface, POO Slot-Observation,
;;; and 7-Band C4 Plural Profile Convergence.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :clan/poo/type define-type validate element? Record String Symbol
                 Bool List Enum Exactly OrFalse Any Fun))
(export +convergence-schema+
        SlotStage SlotCombiner ConvergenceBand ActivationKind
        SlotSpec make-slot-spec
        GovernanceEnvelope make-governance-envelope governance-envelope-meet
        TagSelector by-tag tag-selector?
        FeatureConvergenceDecl make-feature-decl
        ModuleConvergenceDecl make-module-decl
        GlobalProfileDecl make-global-profile
        ActivationReceipt make-activation-receipt
        ConvergenceDiagnostic make-convergence-diagnostic
        ConvergenceResult make-convergence-result)

(def +convergence-schema+ "yuanxu.c4-profile-convergence.v1")

(define-type SlotStage (Enum assembly runtime))
(define-type SlotCombiner (Enum exclusive refine union meet))
(define-type ConvergenceBand
  (Enum core-defaults implied-bridge explicit-feature derived-profiles
        global-profiles module-profiles governance-floor))
(define-type ActivationKind
  (Enum explicit implied derived tag-targeted vetoed))

(define-type SlotSpec
  (Record kind: [(Exactly 'convergence-slot-spec)]
          name: [Symbol]
          stage: [SlotStage]
          combiner: [SlotCombiner]
          default-value: [Any]
          allowed-values: [(OrFalse (List Any))]
          meet-fn: [(OrFalse Any)]))

(def (make-slot-spec name
                     stage: (stage 'assembly)
                     combiner: (combiner 'exclusive)
                     default: (default-val #f)
                     allowed: (allowed-vals #f)
                     meet: (meet-fn #f))
  (validate SlotSpec
            (.o bind-these: #f
                kind: 'convergence-slot-spec
                name: name
                stage: stage
                combiner: combiner
                default-value: default-val
                allowed-values: allowed-vals
                meet-fn: meet-fn)))

(define-type GovernanceEnvelope
  (Record kind: [(Exactly 'governance-envelope)]
          trust-ceiling: [Any]
          allow-network: [Bool]
          allow-write: [Bool]))

(def (make-governance-envelope trust-ceiling allow-network allow-write)
  (validate GovernanceEnvelope
            (.o bind-these: #f
                kind: 'governance-envelope
                trust-ceiling: trust-ceiling
                allow-network: allow-network
                allow-write: allow-write)))

(def (governance-envelope-meet a b)
  (make-governance-envelope
   (min (.ref a 'trust-ceiling) (.ref b 'trust-ceiling))
   (and (.ref a 'allow-network) (.ref b 'allow-network))
   (and (.ref a 'allow-write) (.ref b 'allow-write))))

(define-type TagSelector
  (Record kind: [(Exactly 'by-tag-selector)]
          tag: [Symbol]))

(def (by-tag tag)
  (validate TagSelector (.o bind-these: #f kind: 'by-tag-selector tag: tag)))

(def (tag-selector? v) (element? TagSelector v))

(define-type FeatureConvergenceDecl
  (Record kind: [(Exactly 'feature-convergence-decl)]
          feature-id: [Symbol]
          owner-module-id: [Symbol]
          enabled-fn: [(OrFalse Any)]
          requires: [(List Symbol)]
          conflicts: [(List Symbol)]
          contributions: [Any]))

(def (make-feature-decl owner-id feature-name
                        enabled-fn: (enabled-fn #f)
                        requires: (requires '())
                        conflicts: (conflicts '())
                        contributions: (contributions (.o)))
  (let ((fid (string->symbol
              (string-append (symbol->string owner-id) "/" (symbol->string feature-name)))))
    (validate FeatureConvergenceDecl
              (.o bind-these: #f
                  kind: 'feature-convergence-decl
                  feature-id: fid
                  owner-module-id: owner-id
                  enabled-fn: enabled-fn
                  requires: requires
                  conflicts: conflicts
                  contributions: contributions))))

(define-type ModuleConvergenceDecl
  (Record kind: [(Exactly 'module-convergence-decl)]
          identity: [Symbol]
          tags: [(List Symbol)]
          slot-specs: [(List SlotSpec)]
          defaults: [Any]
          features: [(List FeatureConvergenceDecl)]
          profiles-table: [Any]
          governance-floor: [(OrFalse Any)]))

(def (make-module-decl identity
                       tags: (tags '())
                       slot-specs: (slot-specs '())
                       defaults: (defaults (.o))
                       features: (features '())
                       profiles: (profiles-table (.o))
                       governance-floor: (governance-floor #f))
  (validate ModuleConvergenceDecl
            (.o bind-these: #f
                kind: 'module-convergence-decl
                identity: identity
                tags: tags
                slot-specs: slot-specs
                defaults: defaults
                features: features
                profiles-table: profiles-table
                governance-floor: governance-floor)))

(define-type GlobalProfileDecl
  (Record kind: [(Exactly 'global-profile-decl)]
          profile-id: [Symbol]
          targets: [(List Any)]
          values: [Any]))

(def (make-global-profile profile-id targets values)
  (validate GlobalProfileDecl
            (.o bind-these: #f
                kind: 'global-profile-decl
                profile-id: profile-id
                targets: targets
                values: values)))

(define-type ActivationReceipt
  (Record kind: [(Exactly 'activation-receipt)]
          identity: [Any]
          band: [ConvergenceBand]
          stage: [SlotStage]
          activation: [ActivationKind]
          observed-reads: [(List Any)]
          reason: [String]))

(def (make-activation-receipt identity band stage activation observed-reads reason)
  (validate ActivationReceipt
            (.o bind-these: #f
                kind: 'activation-receipt
                identity: identity
                band: band
                stage: stage
                activation: activation
                observed-reads: observed-reads
                reason: reason)))

(define-type ConvergenceDiagnostic
  (Record kind: [(Exactly 'convergence-diagnostic)]
          code: [Symbol]
          module-id: [Any]
          slot: [Any]
          left-source: [Any]
          right-source: [Any]
          detail: [String]))

(def (make-convergence-diagnostic code module-id slot left-source right-source detail)
  (validate ConvergenceDiagnostic
            (.o bind-these: #f
                kind: 'convergence-diagnostic
                code: code
                module-id: module-id
                slot: slot
                left-source: left-source
                right-source: right-source
                detail: detail)))

(define-type ConvergenceResult
  (Record kind: [(Exactly 'convergence-result)]
          schema: [(Exactly +convergence-schema+)]
          status: [(Enum ready rejected)]
          admitted-modules: [(List Symbol)]
          active-features: [(List Symbol)]
          compiled-closure: [(List Symbol)]
          effective-configs: [Any]
          receipts: [(List ActivationReceipt)]
          diagnostics: [(List ConvergenceDiagnostic)]))

(def (make-convergence-result status admitted-modules active-features compiled-closure
                              effective-configs receipts diagnostics)
  (validate ConvergenceResult
            (.o bind-these: #f
                kind: 'convergence-result
                schema: +convergence-schema+
                status: status
                admitted-modules: admitted-modules
                active-features: active-features
                compiled-closure: compiled-closure
                effective-configs: effective-configs
                receipts: receipts
                diagnostics: diagnostics)))
