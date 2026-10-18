-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.ModuleSystem.Ownership

namespace PooFlowCoreProof.ModuleSystem.Source.Namespaces

inductive NamespaceRole where
  | repositorySource
  | projectionModule
  | profileBinding
  | governanceLanguage
  deriving DecidableEq, Repr

def MaySubstituteNamespaceRole :
    NamespaceRole → NamespaceRole → Prop
  | source, target =>
      if source = target then True else False

inductive ProjectionImplementationStatus where
  | proposedContract
  | implementedAndVerified
  deriving DecidableEq, Repr

def MayClaimImportableModule :
    ProjectionImplementationStatus → Prop
  | .implementedAndVerified => True
  | .proposedContract => False

structure RepositorySourceNamespace
    (RepositoryIdentity CommitIdentity ProvenanceIdentity : Type) where
  repositoryIdentity : RepositoryIdentity
  commitIdentity : CommitIdentity
  provenanceIdentity : ProvenanceIdentity
  providesModulePath : Prop
  noModulePath : ¬ providesModulePath
  providesPackageIdentity : Prop
  noPackageIdentity : ¬ providesPackageIdentity
  providesLexicalBinding : Prop
  noLexicalBinding : ¬ providesLexicalBinding
  providesGovernanceLanguage : Prop
  noGovernanceLanguage : ¬ providesGovernanceLanguage
  providesRuntimeCapability : Prop
  noRuntimeCapability : ¬ providesRuntimeCapability

structure CoreOwnedProjectionNamespace
    (OwnerIdentity ProjectionIdentity : Type) where
  ownerIdentity : OwnerIdentity
  projectionIdentity : ProjectionIdentity
  status : ProjectionImplementationStatus
  occupiesChildOwnedWendaoNamespace : Prop
  noChildNamespaceOccupation : ¬ occupiesChildOwnedWendaoNamespace
  occupiesGovernanceLanguageNamespace : Prop
  noLanguageNamespaceOccupation : ¬ occupiesGovernanceLanguageNamespace

structure ExportedProfileBinding
    (BindingIdentity ProfileIdentity : Type) where
  bindingIdentity : BindingIdentity
  profileIdentity : ProfileIdentity
  firstClassPooValue : Prop
  firstClassEstablished : firstClassPooValue

structure GovernanceLanguageReservation
    (NamespaceIdentity : Type) where
  namespaceIdentity : NamespaceIdentity
  explicitlyGovernanceLanguage : Prop
  governanceRoleEstablished : explicitlyGovernanceLanguage
  implementationExists : Prop
  notYetImplemented : ¬ implementationExists
  genericLangAliasAllowed : Prop
  noGenericLangAlias : ¬ genericLangAliasAllowed

structure ComposeLookupBoundary where
  resolvesRepositoryName : Prop
  resolvesModulePath : Prop
  resolvesPackageManagerState : Prop
  resolvesGlobalRegistry : Prop
  pureValueBoundary :
    ¬ resolvesRepositoryName ∧
      ¬ resolvesModulePath ∧
      ¬ resolvesPackageManagerState ∧
      ¬ resolvesGlobalRegistry

structure ExplicitImportAndBinding
    (ModuleNamespaceIdentity BindingIdentity ProfileIdentity : Type) where
  moduleNamespaceIdentity : ModuleNamespaceIdentity
  bindingIdentity : BindingIdentity
  profileIdentity : ProfileIdentity
  importExplicit : Prop
  explicitImportEstablished : importExplicit

theorem repositoryCannotSubstituteForModuleNamespace :
    ¬ MaySubstituteNamespaceRole
      .repositorySource .projectionModule := by
  simp [MaySubstituteNamespaceRole]

theorem repositoryCannotSubstituteForProfileBinding :
    ¬ MaySubstituteNamespaceRole
      .repositorySource .profileBinding := by
  simp [MaySubstituteNamespaceRole]

theorem moduleCannotSubstituteForGovernanceLanguage :
    ¬ MaySubstituteNamespaceRole
      .projectionModule .governanceLanguage := by
  simp [MaySubstituteNamespaceRole]

theorem profileBindingCannotSubstituteForGovernanceLanguage :
    ¬ MaySubstituteNamespaceRole
      .profileBinding .governanceLanguage := by
  simp [MaySubstituteNamespaceRole]

theorem proposedProjectionCannotClaimImportableModule :
    ¬ MayClaimImportableModule .proposedContract := by
  simp [MayClaimImportableModule]

theorem verifiedProjectionMayClaimImportableModule :
    MayClaimImportableModule .implementedAndVerified := by
  simp [MayClaimImportableModule]

end PooFlowCoreProof.ModuleSystem.Source.Namespaces
