-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.Absence
import LeanPoo.Functional.CertifiedRequirements

import PooFlowCoreProof.ModuleSystem.Graph.Roles

namespace PooFlowCoreProof.ModuleSystem.Selection.Requirements

inductive ResolutionOutcomeKind where
  | exactContribution
  | aggregatedContributions
  | admittedAbsence
  | missing
  | incomplete
  | ambiguous
  | incompatible
  deriving DecidableEq, Repr

def AdmitsSemanticResolution : ResolutionOutcomeKind → Prop
  | .exactContribution => True
  | .aggregatedContributions => True
  | .admittedAbsence => True
  | .missing => False
  | .incomplete => False
  | .ambiguous => False
  | .incompatible => False

structure SemanticRequirement
    (RequirementIdentity ContractIdentity ScopeIdentity
      SelectionPolicyIdentity FailurePolicyIdentity : Type) where
  requirementIdentity : RequirementIdentity
  contractIdentity : ContractIdentity
  scopeIdentity : ScopeIdentity
  selectionPolicyIdentity : SelectionPolicyIdentity
  failurePolicyIdentity : FailurePolicyIdentity
  immutableObject : Prop
  immutabilityEstablished : immutableObject

structure SemanticContribution
    (ContributionIdentity RevisionIdentity ContractIdentity ScopeIdentity
      SlotIdentity PriorityIdentity CapabilityContractIdentity : Type) where
  contributionIdentity : ContributionIdentity
  revisionIdentity : RevisionIdentity
  contractIdentity : ContractIdentity
  scopeIdentity : ScopeIdentity
  slotIdentity : SlotIdentity
  priorityIdentity : PriorityIdentity
  capabilityContractIdentity : CapabilityContractIdentity
  carriesLiveCapabilityToken : Prop
  noLiveCapabilityToken : ¬ carriesLiveCapabilityToken

structure DirectionalCompatibility where
  offeredSatisfiesRequired : Prop
  requesterAcceptsRevisionAndSchema : Prop
  capabilityScopeDoesNotEscalate : Prop
  confidentialityProjectionSufficient : Prop
  lifecycleConstraintsHold : Prop
  compatibilityEstablished :
    offeredSatisfiesRequired ∧
      requesterAcceptsRevisionAndSchema ∧
      capabilityScopeDoesNotEscalate ∧
      confidentialityProjectionSufficient ∧
      lifecycleConstraintsHold

structure SlotPriorityBoundary where
  slotLocalPriority : Prop
  slotLocalEstablished : slotLocalPriority
  globalProfilePriority : Prop
  noGlobalProfilePriority : ¬ globalProfilePriority
  operandOrderSelectsWinner : Prop
  noOperandOrderWinner : ¬ operandOrderSelectsWinner

structure StructuralResolution where
  topologyDependsOnLiveValue : Prop
  noLiveValueTopology : ¬ topologyDependsOnLiveValue

structure CyclicRequirementResolution
    (RequirementIdentity ComponentIdentity : Type) where
  requirements : List RequirementIdentity
  componentIdentity : ComponentIdentity
  representedAsSemanticScc : Prop
  sccEstablished : representedAsSemanticScc

structure RequirementResolutionReceipt
    (RequesterIdentity RequirementIdentity CandidateSetIdentity
      PolicyIdentity EvidenceCutIdentity ResultIdentity ReceiptIdentity : Type)
    where
  requesterIdentity : RequesterIdentity
  requirementIdentity : RequirementIdentity
  candidateSetIdentity : CandidateSetIdentity
  policyIdentity : PolicyIdentity
  evidenceCutIdentity : EvidenceCutIdentity
  resultIdentity : ResultIdentity
  receiptIdentity : ReceiptIdentity
  identityComplete : Prop
  completenessEstablished : identityComplete

theorem exactContributionAdmitsResolution :
    AdmitsSemanticResolution .exactContribution := by
  simp [AdmitsSemanticResolution]

theorem aggregateAdmitsResolution :
    AdmitsSemanticResolution .aggregatedContributions := by
  simp [AdmitsSemanticResolution]

theorem admittedAbsenceAdmitsResolution :
    AdmitsSemanticResolution .admittedAbsence := by
  simp [AdmitsSemanticResolution]

theorem missingRequirementFailsClosed :
    ¬ AdmitsSemanticResolution .missing := by
  simp [AdmitsSemanticResolution]

theorem incompleteEvidenceFailsClosed :
    ¬ AdmitsSemanticResolution .incomplete := by
  simp [AdmitsSemanticResolution]

theorem ambiguousCandidatesFailClosed :
    ¬ AdmitsSemanticResolution .ambiguous := by
  simp [AdmitsSemanticResolution]

open LeanPoo.Functional
open LeanPoo.Functional.Requirements

/-- Every successfully resolved capability has an ancestor in the supplied C4
snapshot. No loaded-module registry or filesystem discovery participates. -/
theorem resolvedCapabilitiesHaveDeclaredOrigin
    {Context Key : Type} {Value : Context → Key → Type}
    (order : LeanPoo.C4.VerifiedOrder graph root)
    (providers : String → Provider Context Key Value) (keys : List Key)
    (factories : Factories Context Value keys)
    (resolved : prepare (assemble order providers) keys = .ok factories)
    (key : Key) (required : key ∈ keys) :
    ∃ name, LeanPoo.C4.Ancestor graph name root ∧
      ∃ factory, providers name key = some factory :=
  prepare_origin order providers keys factories resolved key required

/-- Admitted absence is a checked negative capability certificate, not a tag
which can be supplied alongside an actually present contribution. -/
theorem admittedAbsenceCannotHaveProvider
    {Context Key : Type} {Value : Context → Key → Type}
    {provider : Provider Context Key Value} {keys : List Key}
    (absence : AbsenceCertificate provider keys) (key : Key) (required : key ∈ keys)
    (factory : Factory Context (fun c => Value c key)) :
    provider key ≠ some factory := by
  rw [absence.absent key required]
  simp

end PooFlowCoreProof.ModuleSystem.Selection.Requirements
