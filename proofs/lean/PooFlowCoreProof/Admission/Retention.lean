-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.Decision

namespace PooFlowCoreProof.Admission.Retention

open PooFlowCoreProof.Admission.Decision

inductive RetentionOutcomeKind where
  | retained
  | redactedProjection
  | checkpointCompacted
  | erasureCandidate
  | erased
  | suspended
  deriving DecidableEq, Repr

def MutatesLogicalHistory : RetentionOutcomeKind → Prop
  | .retained => False
  | .redactedProjection => False
  | .checkpointCompacted => False
  | .erasureCandidate => False
  | .erased => False
  | .suspended => False

def CarriesDestructiveAuthority : RetentionOutcomeKind → Prop
  | .retained => False
  | .redactedProjection => False
  | .checkpointCompacted => False
  | .erasureCandidate => False
  | .erased => False
  | .suspended => False

structure CanonicalReceiptHeader
    (EvidenceIdentity SchemaIdentity CommitmentIdentity : Type) where
  evidenceIdentity : EvidenceIdentity
  schemaIdentity : SchemaIdentity
  contentCommitment : CommitmentIdentity
  immutableHistory : Prop
  immutabilityEstablished : immutableHistory

structure ErasureAdmissionChecks where
  retentionWindowExpired : Prop
  noLegalHold : Prop
  checkpointCoverageEstablished : Prop
  replayRequirementsPreserved : Prop
  referenceClosureEstablished : Prop
  governanceCapabilityValid : Prop
  replicaPlanComplete : Prop

def ErasureChecksHold (checks : ErasureAdmissionChecks) : Prop :=
  checks.retentionWindowExpired ∧
    checks.noLegalHold ∧
    checks.checkpointCoverageEstablished ∧
    checks.replayRequirementsPreserved ∧
    checks.referenceClosureEstablished ∧
    checks.governanceCapabilityValid ∧
    checks.replicaPlanComplete

structure ErasureAdmissionReceipt
    (EvidenceIdentity PolicyIdentity ObservationIdentity ReceiptIdentity : Type)
    where
  evidenceIdentity : EvidenceIdentity
  policyIdentity : PolicyIdentity
  observationIdentity : ObservationIdentity
  checks : ErasureAdmissionChecks
  checksHold : ErasureChecksHold checks
  receiptIdentity : ReceiptIdentity

structure DisclosureProjection
    (EvidenceIdentity ProjectionIdentity CommitmentIdentity : Type) where
  sourceEvidenceIdentity : EvidenceIdentity
  projectionIdentity : ProjectionIdentity
  sourceCommitment : CommitmentIdentity
  commitmentPreserved : Prop
  preservationEstablished : commitmentPreserved
  claimsPhysicalErasure : Prop
  noErasureClaim : ¬ claimsPhysicalErasure

structure CheckpointCoverage
    (CheckpointIdentity EvidenceRangeIdentity ReplayContractIdentity : Type)
    where
  checkpointIdentity : CheckpointIdentity
  coveredEvidenceRange : EvidenceRangeIdentity
  replayContractIdentity : ReplayContractIdentity
  coverageEstablished : Prop
  coverageProof : coverageEstablished
  replayPreserved : Prop
  replayProof : replayPreserved

structure LegalHoldObservation
    (EvidenceIdentity HoldIdentity : Type) where
  evidenceIdentity : EvidenceIdentity
  holdIdentity : HoldIdentity
  holdActive : Prop
  activeEstablished : holdActive
  erasureAllowed : Prop
  activeHoldPreventsErasure : ¬ erasureAllowed

structure ReferenceClosureEvidence
    (EvidenceIdentity ReferenceIdentity : Type) where
  evidenceIdentity : EvidenceIdentity
  outstandingReferences : List ReferenceIdentity
  noOutstandingReferences : outstandingReferences = []

structure PhysicalErasureReceipt
    (EvidenceIdentity KeyIdentity ReplicaIdentity ReceiptIdentity : Type) where
  evidenceIdentity : EvidenceIdentity
  destroyedKey : KeyIdentity
  purgedReplicas : List ReplicaIdentity
  requiredReplicas : List ReplicaIdentity
  everyRequiredReplicaPurged :
    ∀ replica ∈ requiredReplicas,
      replica ∈ purgedReplicas
  payloadUnavailable : Prop
  unavailabilityEstablished : payloadUnavailable
  logicalHeaderPreserved : Prop
  headerPreservationEstablished : logicalHeaderPreserved
  receiptIdentity : ReceiptIdentity

structure GovernedErasureAuthorization
    (ProposalIdentity ScopeIdentity ActionRole CapabilityIdentity : Type) where
  capability :
    OneShotScopedCapability
      ProposalIdentity ScopeIdentity ActionRole CapabilityIdentity

theorem retentionNeverRewritesLogicalHistory
    (outcome : RetentionOutcomeKind) :
    ¬ MutatesLogicalHistory outcome := by
  cases outcome <;> simp [MutatesLogicalHistory]

theorem retentionProposalCarriesNoDestructiveAuthority
    (outcome : RetentionOutcomeKind) :
    ¬ CarriesDestructiveAuthority outcome := by
  cases outcome <;> simp [CarriesDestructiveAuthority]

end PooFlowCoreProof.Admission.Retention
