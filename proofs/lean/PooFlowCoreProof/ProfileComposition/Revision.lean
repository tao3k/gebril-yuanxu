-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.ContextSlot
import PooFlowCoreProof.Graph.Cache

import PooFlowCoreProof.ModuleSystem.Selection.Requirements

namespace PooFlowCoreProof.ProfileComposition.Revision

inductive UpgradeMechanismKind where
  | newImmutableRevision
  | inPlaceMutation
  | moduleReloadRewrite
  deriving DecidableEq, Repr

def AdmitsProfileUpgrade : UpgradeMechanismKind → Prop
  | .newImmutableRevision => True
  | .inPlaceMutation => False
  | .moduleReloadRewrite => False

structure ProfileRevision
    (ModuleArtifactIdentity ProfileRevisionIdentity ConstructionIdentity
      ContractIdentity CapabilityContractIdentity : Type) where
  moduleArtifactIdentity : ModuleArtifactIdentity
  profileRevisionIdentity : ProfileRevisionIdentity
  constructionIdentity : ConstructionIdentity
  contractIdentity : ContractIdentity
  capabilityContractIdentity : CapabilityContractIdentity
  immutableValue : Prop
  immutabilityEstablished : immutableValue

structure UpgradeRevisionBundle
    (ModuleArtifactIdentity ProfileRevisionIdentity RootRevisionIdentity
      GenerationIdentity ActiveHeadIdentity : Type) where
  moduleArtifactIdentity : ModuleArtifactIdentity
  profileRevisionIdentity : ProfileRevisionIdentity
  rootRevisionIdentity : RootRevisionIdentity
  generationIdentity : GenerationIdentity
  activeHeadIdentity : ActiveHeadIdentity

structure StableBindingBoundary
    (BindingIdentity ProfileRevisionIdentity : Type) where
  bindingIdentity : BindingIdentity
  capturedRevision : ProfileRevisionIdentity
  currentlyExportedRevision : ProfileRevisionIdentity
  dynamicallyResolvesNewestRevision : Prop
  noDynamicRevisionResolution : ¬ dynamicallyResolvesNewestRevision

structure ConcurrentArtifactIsolation
    (OldArtifactIdentity NewArtifactIdentity : Type) where
  oldArtifactIdentity : OldArtifactIdentity
  newArtifactIdentity : NewArtifactIdentity
  storageIsolated : Prop
  moduleInstancesIsolated : Prop
  runtimeStateIsolated : Prop
  isolationEstablished :
    storageIsolated ∧ moduleInstancesIsolated ∧ runtimeStateIsolated

structure ProfileRevisionDelta
    (OldRevisionIdentity NewRevisionIdentity DeltaIdentity : Type) where
  oldRevisionIdentity : OldRevisionIdentity
  newRevisionIdentity : NewRevisionIdentity
  deltaIdentity : DeltaIdentity
  semanticEvidenceComplete : Prop
  semanticEvidenceEstablished : semanticEvidenceComplete
  textDiffIsSemanticProof : Prop
  textDiffNotProof : ¬ textDiffIsSemanticProof

structure ProfileRevisionEquivalence
    (OldRevisionIdentity NewRevisionIdentity ProofIdentity : Type) where
  oldRevisionIdentity : OldRevisionIdentity
  newRevisionIdentity : NewRevisionIdentity
  proofIdentity : ProofIdentity
  semanticCacheReuseAllowed : Prop
  sccProofReuseAllowed : Prop
  mergesRevisionIdentities : Prop
  identitiesRemainDistinct : ¬ mergesRevisionIdentities
  reusesOldApproval : Prop
  noApprovalReuse : ¬ reusesOldApproval
  reusesOldCapability : Prop
  noCapabilityReuse : ¬ reusesOldCapability

structure ContinuationRevisionBinding
    (GenerationIdentity RootRevisionIdentity ProfileRevisionIdentity
      EvidenceIdentity EffectObligationIdentity : Type) where
  generationIdentity : GenerationIdentity
  rootRevisionIdentity : RootRevisionIdentity
  profileRevisions : List ProfileRevisionIdentity
  evidenceIdentity : EvidenceIdentity
  effectObligationIdentity : EffectObligationIdentity
  silentlyRebound : Prop
  noSilentRebinding : ¬ silentlyRebound

/-- Complete revision coordinates are compared by the library's context slot;
there is no separate identity function or path-only cache admission. -/
structure RevisionContext (ProfileRevisionIdentity RootRevisionIdentity : Type) where
  profileRevision : ProfileRevisionIdentity
  rootRevision : RootRevisionIdentity
  deriving DecidableEq

open LeanPoo.Functional.Requirements

theorem profileRevisionInvalidatesCachedResult
    {ProfileRevision RootRevision Key : Type} [DecidableEq ProfileRevision] [DecidableEq RootRevision]
    {Value : RevisionContext ProfileRevision RootRevision → Key → Type}
    {keys : List Key} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (before after : RevisionContext ProfileRevision RootRevision)
    (changed : before.profileRevision ≠ after.profileRevision) (data : Snapshot ready before) :
    (({retained := some ⟨before, data⟩} : ContextSlot ready).read after).2.2 = false := by
  apply PooFlowCoreProof.Graph.Cache.changedCutCannotHit before after _ data
  intro same
  exact changed (congrArg RevisionContext.profileRevision same)

structure SourcePinRevision
    (CommitIdentity ProfileRevisionIdentity : Type) where
  previousCommit : CommitIdentity
  revisedCommit : CommitIdentity
  commitChanged : previousCommit ≠ revisedCommit
  previousProfileRevision : ProfileRevisionIdentity
  revisedProfileRevision : ProfileRevisionIdentity
  revisionChanged :
    previousProfileRevision ≠ revisedProfileRevision

structure ReplRevision
    (ArtifactIdentity ProfileRevisionIdentity : Type) where
  artifactIdentity : ArtifactIdentity
  profileRevisionIdentity : ProfileRevisionIdentity
  ephemeral : Prop
  ephemeralEstablished : ephemeral
  admittedAsProduction : Prop
  noProductionAdmission : ¬ admittedAsProduction

structure ReversionPlan
    (GenerationIdentity ActiveHeadIdentity PlanIdentity : Type) where
  targetGenerationIdentity : GenerationIdentity
  newActiveHeadIdentity : ActiveHeadIdentity
  planIdentity : PlanIdentity
  currentCompatibilityReproved : Prop
  artifactAvailabilityReproved : Prop
  currentGovernanceReproved : Prop
  checksEstablished :
    currentCompatibilityReproved ∧
      artifactAvailabilityReproved ∧
      currentGovernanceReproved
  reusesStaleCapability : Prop
  noStaleCapabilityReuse : ¬ reusesStaleCapability

theorem immutableRevisionUpgradeIsAdmitted :
    AdmitsProfileUpgrade .newImmutableRevision := by
  simp [AdmitsProfileUpgrade]

theorem inPlaceProfileMutationIsRejected :
    ¬ AdmitsProfileUpgrade .inPlaceMutation := by
  simp [AdmitsProfileUpgrade]

theorem moduleReloadRootRewriteIsRejected :
    ¬ AdmitsProfileUpgrade .moduleReloadRewrite := by
  simp [AdmitsProfileUpgrade]


end PooFlowCoreProof.ProfileComposition.Revision
