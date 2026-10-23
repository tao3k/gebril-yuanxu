;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: reusable POO module identity and directional contribution relations.
;;; Authoring roles and source-file policy belong to the consuming package.
(import (only-in :clan/poo/object .o .mix .ref)
        (only-in :clan/poo/mop define-type validate)
        (only-in :yuanxu/object-types/contracts
                 YuanxuContract. YuanxuObjectContract.
                 yuanxu-classification-evidence))
(export SemanticSymbol
        ModuleIdentityContract ModuleImportsContract ModuleProfilesContract
        ModuleCapabilitiesContract ImportContributionContract
        SemanticImports. SemanticProfiles. SemanticCapabilities.
        ModuleIdentity. ImportContribution.
        yuanxu-semantic-identity yuanxu-empty-imports
        yuanxu-empty-profiles yuanxu-empty-capabilities
        yuanxu-import-contribution yuanxu-module-imports)

(def (semantic-symbol-classify candidate context)
  (yuanxu-classification-evidence
   'semantic-symbol candidate (symbol? candidate)
   (if (symbol? candidate) '() '(expected-symbol)) context))

(define-type (SemanticSymbol @ YuanxuContract.)
  identity: 'semantic-symbol
  .classify: semantic-symbol-classify)

(define-type (ModuleIdentityContract @ YuanxuObjectContract.)
  identity: 'module-identity
  proto: (.o)
  responsibilities: (.o namespace: SemanticSymbol name: SemanticSymbol))

;;; Distinct prototypes prevent import/profile contribution ancestry from aliasing.
(define-type (ModuleImportsContract @ YuanxuObjectContract.)
  identity: 'module-imports
  proto: (.o contributions: '())
  responsibilities: (.o))

(define-type (ModuleProfilesContract @ YuanxuObjectContract.)
  identity: 'module-profiles
  proto: (.o contributions: '())
  responsibilities: (.o))

(define-type (CapabilityRequirementsContract @ YuanxuObjectContract.)
  identity: 'capability-requirements
  proto: (.o contributions: '())
  responsibilities: (.o))

(define-type (CapabilityProvisionsContract @ YuanxuObjectContract.)
  identity: 'capability-provisions
  proto: (.o contributions: '())
  responsibilities: (.o))

(define-type (ModuleCapabilitiesContract @ YuanxuObjectContract.)
  identity: 'module-capabilities
  proto: (.o)
  responsibilities:
  (.o requirements: CapabilityRequirementsContract
      provisions: CapabilityProvisionsContract))

(define-type (ImportContributionContract @ YuanxuObjectContract.)
  identity: 'import-contribution
  proto: (.o)
  responsibilities:
  (.o identity: ModuleIdentityContract
      owner: ModuleIdentityContract
      instance: ModuleIdentityContract
      source: ModuleIdentityContract
      revision: SemanticSymbol))

(def SemanticImports. (.ref ModuleImportsContract 'proto))
(def SemanticProfiles. (.ref ModuleProfilesContract 'proto))
(def SemanticCapabilities. (.ref ModuleCapabilitiesContract 'proto))
(def ModuleIdentity. (.ref ModuleIdentityContract 'proto))
(def ImportContribution. (.ref ImportContributionContract 'proto))
(def CapabilityResponsibilities.
  (.ref ModuleCapabilitiesContract 'responsibilities))
(def CapabilityRequirements.
  (.ref (.ref CapabilityResponsibilities. 'requirements) 'proto))
(def CapabilityProvisions.
  (.ref (.ref CapabilityResponsibilities. 'provisions) 'proto))

(def (yuanxu-semantic-identity namespace-value name-value)
  (validate ModuleIdentityContract
    (.o (:: @ ModuleIdentity.)
        namespace: namespace-value name: name-value)))

(def (yuanxu-empty-imports) (.mix SemanticImports.))
(def (yuanxu-empty-profiles) (.mix SemanticProfiles.))
(def (yuanxu-empty-capabilities)
  (.o (:: @ SemanticCapabilities.)
      requirements: (.mix CapabilityRequirements.)
      provisions: (.mix CapabilityProvisions.)))

(def (yuanxu-import-contribution identity-value owner-value instance-value
                                   source-value revision-value target-value)
  (validate ImportContributionContract
    (.o (:: @ ImportContribution.)
        identity: identity-value owner: owner-value instance: instance-value
        source: source-value revision: revision-value target: target-value)))

(def (yuanxu-module-imports . contribution-values)
  (.o (:: @ SemanticImports.)
      (contributions => yuanxu-import-contributions-before
                     contribution-values)))

;;; C4 owns ancestry and diamond de-duplication; this slot rule only states
;;; the domain-specific order within that ancestry.
(def (yuanxu-import-contributions-before inherited local)
  (append local inherited))
