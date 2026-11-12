-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import YuanxuProof.Modules.Funflow.ConclusionRevision

namespace YuanxuProof.Admission.Decision

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

/-- Concrete decision inputs. These are observations, not assertions of admission.
Identity checks compare full projected identities; signature authenticity is external. -/
structure GovernanceChecks where
  proposal : Nat
  expectedProposal : Nat
  evidenceCut : Nat
  expectedEvidenceCut : Nat
  approvers : List Nat
  threshold : Nat
  proposer : Nat
  executor : Nat
  scope : Nat
  expectedScope : Nat
  version : Nat
  expectedVersion : Nat
  policy : Nat
  expectedPolicy : Nat
  observedAt : Nat
  expiresAt : Nat
  revoked : Bool
  deriving DecidableEq, Repr

def GovernanceChecksHold (checks : GovernanceChecks) : Prop :=
  checks.proposal = checks.expectedProposal ∧
  checks.evidenceCut = checks.expectedEvidenceCut ∧
  checks.threshold ≤ checks.approvers.eraseDups.length ∧
  checks.proposer ∉ checks.approvers ∧ checks.executor ∉ checks.approvers ∧
  checks.scope = checks.expectedScope ∧
  checks.version = checks.expectedVersion ∧
  checks.policy = checks.expectedPolicy ∧
  checks.observedAt ≤ checks.expiresAt ∧ checks.revoked = false

instance (checks : GovernanceChecks) : Decidable (GovernanceChecksHold checks) :=
  inferInstanceAs (Decidable (_ ∧ _))

def admitGovernance (checks : GovernanceChecks) : Option {c : GovernanceChecks // GovernanceChecksHold c} :=
  if valid : GovernanceChecksHold checks then some ⟨checks, valid⟩ else none

theorem revokedCannotBeAdmitted (checks : GovernanceChecks) (revoked : checks.revoked = true) :
    admitGovernance checks = none := by
  have invalid : ¬ GovernanceChecksHold checks := by
    intro valid
    have := valid.2.2.2.2.2.2.2.2.2
    simp [revoked] at this
  simp [admitGovernance, invalid]

/-- Approval identities are normalized before counting. There is no caller-supplied
threshold proposition or certificate of a count that was never computed. -/
structure QuorumEvidence (PrincipalIdentity : Type) where
  approvingPrincipals : List PrincipalIdentity
  threshold : Nat

def quorumSatisfied (quorum : QuorumEvidence PrincipalIdentity) [DecidableEq PrincipalIdentity] : Prop :=
  quorum.threshold ≤ quorum.approvingPrincipals.eraseDups.length

instance (quorum : QuorumEvidence PrincipalIdentity) [DecidableEq PrincipalIdentity] :
    Decidable (quorumSatisfied quorum) := inferInstanceAs (Decidable (_ ≤ _))

def admitQuorum [DecidableEq PrincipalIdentity] (quorum : QuorumEvidence PrincipalIdentity) :
    Option {q : QuorumEvidence PrincipalIdentity // quorumSatisfied q} :=
  if valid : quorumSatisfied quorum then some ⟨quorum, valid⟩ else none

#guard admitQuorum (⟨[1, 1], 2⟩ : QuorumEvidence Nat) |>.isNone
#guard admitQuorum (⟨[1, 2], 2⟩ : QuorumEvidence Nat) |>.isSome

structure SeparationOfDuties
    (PrincipalIdentity : Type) where
  proposer : PrincipalIdentity
  approver : PrincipalIdentity
  executor : PrincipalIdentity
  proposerNotApprover : proposer ≠ approver
  approverNotExecutor : approver ≠ executor

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

end YuanxuProof.Admission.Decision
