-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Graph.ConclusionRevision

namespace PooFlowCoreProof.Admission.Decision

inductive GovernanceDecisionKind where
  | candidateEvidence
  | satisfied
  | expired
  | revoked
  | invalid
  deriving DecidableEq, Repr

def MayRequestScopedCapability : GovernanceDecisionKind → Prop
  | .satisfied => True
  | .candidateEvidence => False
  | .expired => False
  | .revoked => False
  | .invalid => False

def GovernanceEvidenceCarriesActionAuthority :
    GovernanceDecisionKind → Prop
  | .candidateEvidence => False
  | .satisfied => False
  | .expired => False
  | .revoked => False
  | .invalid => False

structure GovernanceChecks where
  exactProposal : Prop
  exactEvidenceCut : Prop
  quorumSatisfied : Prop
  separationSatisfied : Prop
  scopeMatches : Prop
  versionPreconditionHolds : Prop
  policyMatches : Prop
  temporalRequirementsHold : Prop
  notRevoked : Prop

def GovernanceChecksHold (checks : GovernanceChecks) : Prop :=
  checks.exactProposal ∧
    checks.exactEvidenceCut ∧
    checks.quorumSatisfied ∧
    checks.separationSatisfied ∧
    checks.scopeMatches ∧
    checks.versionPreconditionHolds ∧
    checks.policyMatches ∧
    checks.temporalRequirementsHold ∧
    checks.notRevoked

structure GovernanceDecisionReceipt
    (ProposalIdentity EvidenceCutIdentity PolicyIdentity ScopeIdentity
      DecisionIdentity : Type) where
  proposalIdentity : ProposalIdentity
  evidenceCutIdentity : EvidenceCutIdentity
  policyIdentity : PolicyIdentity
  scopeIdentity : ScopeIdentity
  checks : GovernanceChecks
  checksHold : GovernanceChecksHold checks
  decisionIdentity : DecisionIdentity

structure QuorumEvidence (PrincipalIdentity : Type) where
  approvingPrincipals : List PrincipalIdentity
  principalsDistinct : approvingPrincipals.Nodup
  thresholdSatisfied : Prop
  thresholdEstablished : thresholdSatisfied

structure SeparationOfDuties
    (PrincipalIdentity : Type) where
  proposer : PrincipalIdentity
  approver : PrincipalIdentity
  executor : PrincipalIdentity
  proposerNotApprover : proposer ≠ approver
  approverNotExecutor : approver ≠ executor

structure OneShotScopedCapability
    (ProposalIdentity ScopeIdentity ActionRole CapabilityIdentity : Type) where
  proposalIdentity : ProposalIdentity
  scopeIdentity : ScopeIdentity
  actionRole : ActionRole
  capabilityIdentity : CapabilityIdentity
  consumptionCount : Nat
  atMostOnce : consumptionCount ≤ 1

structure CapabilityConsumptionReceipt
    (CapabilityIdentity ActionReceiptIdentity : Type) where
  capabilityIdentity : CapabilityIdentity
  actionReceiptIdentity : ActionReceiptIdentity
  consumptionCount : Nat
  consumedExactlyOnce : consumptionCount = 1

structure GovernanceRevocation
    (DecisionIdentity RevocationIdentity : Type) where
  decisionIdentity : DecisionIdentity
  revocationIdentity : RevocationIdentity
  capabilityIssuanceAllowed : Prop
  issuanceFailsClosed : ¬ capabilityIssuanceAllowed

structure BreakGlassDecision
    (ProposalIdentity ScopeIdentity PolicyIdentity TimeObservationIdentity
      ReceiptIdentity : Type) where
  proposalIdentity : ProposalIdentity
  scopeIdentity : ScopeIdentity
  policyIdentity : PolicyIdentity
  timeObservationIdentity : TimeObservationIdentity
  receiptIdentity : ReceiptIdentity
  policyAllowsBreakGlass : Prop
  policyEstablished : policyAllowsBreakGlass
  scopeIsExplicit : Prop
  scopeEstablished : scopeIsExplicit
  expiryIsExplicit : Prop
  expiryEstablished : expiryIsExplicit
  reasonRecorded : Prop
  reasonEstablished : reasonRecorded
  postActionReviewRequired : Prop
  reviewObligationEstablished : postActionReviewRequired
  carriesGlobalAuthority : Prop
  noGlobalAuthority : ¬ carriesGlobalAuthority

theorem candidateApprovalIsNotCapabilityAuthority :
    ¬ GovernanceEvidenceCarriesActionAuthority .candidateEvidence := by
  simp [GovernanceEvidenceCarriesActionAuthority]

theorem satisfiedApprovalStillIsNotActionAuthority :
    ¬ GovernanceEvidenceCarriesActionAuthority .satisfied := by
  simp [GovernanceEvidenceCarriesActionAuthority]

theorem satisfiedDecisionMayRequestScopedCapability :
    MayRequestScopedCapability .satisfied := by
  simp [MayRequestScopedCapability]

theorem expiredDecisionFailsClosed :
    ¬ MayRequestScopedCapability .expired := by
  simp [MayRequestScopedCapability]

theorem revokedDecisionFailsClosed :
    ¬ MayRequestScopedCapability .revoked := by
  simp [MayRequestScopedCapability]

theorem invalidDecisionFailsClosed :
    ¬ MayRequestScopedCapability .invalid := by
  simp [MayRequestScopedCapability]

theorem quorumCarriesDistinctPrincipals
    {PrincipalIdentity : Type}
    (quorum : QuorumEvidence PrincipalIdentity) :
    quorum.approvingPrincipals.Nodup :=
  quorum.principalsDistinct

theorem quorumCarriesThresholdEvidence
    {PrincipalIdentity : Type}
    (quorum : QuorumEvidence PrincipalIdentity) :
    quorum.thresholdSatisfied :=
  quorum.thresholdEstablished

theorem proposerAndApproverAreSeparated
    {PrincipalIdentity : Type}
    (separation : SeparationOfDuties PrincipalIdentity) :
    separation.proposer ≠ separation.approver :=
  separation.proposerNotApprover

theorem approverAndExecutorAreSeparated
    {PrincipalIdentity : Type}
    (separation : SeparationOfDuties PrincipalIdentity) :
    separation.approver ≠ separation.executor :=
  separation.approverNotExecutor

theorem breakGlassRequiresExplicitScopeAndExpiry
    {ProposalIdentity ScopeIdentity PolicyIdentity TimeObservationIdentity
      ReceiptIdentity : Type}
    (decision :
      BreakGlassDecision
        ProposalIdentity ScopeIdentity PolicyIdentity TimeObservationIdentity
        ReceiptIdentity) :
    decision.scopeIsExplicit ∧ decision.expiryIsExplicit :=
  ⟨decision.scopeEstablished, decision.expiryEstablished⟩

end PooFlowCoreProof.Admission.Decision
