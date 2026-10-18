-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.KeyLifecycle

namespace PooFlowCoreProof.Admission.Federation

inductive FederationOutcomeKind where
  | candidate
  | agreed
  | incompatible
  | expired
  | revoked
  deriving DecidableEq, Repr

def MayEnterLocalFederationAdmission : FederationOutcomeKind → Prop
  | .agreed => True
  | .candidate => False
  | .incompatible => False
  | .expired => False
  | .revoked => False

def CreatesGlobalRootAuthority : FederationOutcomeKind → Prop
  | .candidate => False
  | .agreed => False
  | .incompatible => False
  | .expired => False
  | .revoked => False

structure DomainOwnership
    (DomainIdentity OwnershipEvidenceIdentity : Type) where
  domainIdentity : DomainIdentity
  ownershipEvidenceIdentity : OwnershipEvidenceIdentity
  retainsIdentityOwnership : Prop
  retainsPolicyOwnership : Prop
  retainsResourceOwnership : Prop
  retainsCapabilityIssuance : Prop
  retainsGovernance : Prop
  ownershipRetained :
    retainsIdentityOwnership ∧
      retainsPolicyOwnership ∧
      retainsResourceOwnership ∧
      retainsCapabilityIssuance ∧
      retainsGovernance

structure FederationCompatibilityChecks where
  requirementMatchesOffer : Prop
  contractIdentitiesMatch : Prop
  trustAnchorsAccepted : Prop
  disclosureAllowed : Prop
  evidenceRequirementsMet : Prop
  capabilityConstraintsMet : Prop
  responsibilityAllocated : Prop
  temporalRequirementsHold : Prop

def FederationChecksHold (checks : FederationCompatibilityChecks) : Prop :=
  checks.requirementMatchesOffer ∧
    checks.contractIdentitiesMatch ∧
    checks.trustAnchorsAccepted ∧
    checks.disclosureAllowed ∧
    checks.evidenceRequirementsMet ∧
    checks.capabilityConstraintsMet ∧
    checks.responsibilityAllocated ∧
    checks.temporalRequirementsHold

structure FederationAgreement
    (ImportingDomain RemoteDomain RequirementIdentity OfferIdentity
      PolicyIdentity EvidenceCutIdentity AgreementIdentity : Type) where
  importingDomain : ImportingDomain
  remoteDomain : RemoteDomain
  requirementIdentity : RequirementIdentity
  offerIdentity : OfferIdentity
  policyIdentity : PolicyIdentity
  evidenceCutIdentity : EvidenceCutIdentity
  checks : FederationCompatibilityChecks
  checksHold : FederationChecksHold checks
  agreementIdentity : AgreementIdentity

structure CapabilityAttenuation
    (CapabilityIdentity Scope ActionRole Expiry DelegationDepth : Type) where
  sourceCapabilityIdentity : CapabilityIdentity
  attenuatedCapabilityIdentity : CapabilityIdentity
  sourceScope : Scope
  attenuatedScope : Scope
  sourceActionRole : ActionRole
  attenuatedActionRole : ActionRole
  sourceExpiry : Expiry
  attenuatedExpiry : Expiry
  sourceDelegationDepth : DelegationDepth
  attenuatedDelegationDepth : DelegationDepth
  scopeNotAmplified : Prop
  actionNotAmplified : Prop
  expiryNotExtended : Prop
  delegationDepthNotIncreased : Prop
  attenuationEstablished :
    scopeNotAmplified ∧
      actionNotAmplified ∧
      expiryNotExtended ∧
      delegationDepthNotIncreased

structure FederationDisclosureProjection
    (RemoteEvidenceIdentity ProjectionIdentity : Type) where
  remoteEvidenceIdentity : RemoteEvidenceIdentity
  projectionIdentity : ProjectionIdentity
  importsRemoteInternalGraph : Prop
  noImplicitGraphImport : ¬ importsRemoteInternalGraph
  importsRemoteCapabilities : Prop
  noImplicitCapabilityImport : ¬ importsRemoteCapabilities

structure ResponsibilityAllocation
    (RequirementOwner OfferOwner IncidentOwner RevocationOwner
      RetentionOwner ResponsibilityIdentity : Type) where
  requirementOwner : RequirementOwner
  offerOwner : OfferOwner
  incidentOwner : IncidentOwner
  revocationOwner : RevocationOwner
  retentionOwner : RetentionOwner
  responsibilityIdentity : ResponsibilityIdentity
  allocationComplete : Prop
  completenessEstablished : allocationComplete

structure FederationRevocation
    (AgreementIdentity RevocationIdentity : Type) where
  agreementIdentity : AgreementIdentity
  revocationIdentity : RevocationIdentity
  continuedLocalUseAllowed : Prop
  revokedAgreementFailsClosed : ¬ continuedLocalUseAllowed

structure OwnershipTransferAttempt
    (DomainIdentity TransferContractIdentity AuthorityIdentity : Type) where
  domainIdentity : DomainIdentity
  transferContractIdentity : TransferContractIdentity
  authorityIdentity : AuthorityIdentity
  exactTransferContract : Prop
  transferAuthorityValid : Prop
  ownershipTransferred : Prop
  transferRequiresContractAndAuthority :
    ownershipTransferred →
      exactTransferContract ∧ transferAuthorityValid

theorem federationNeverCreatesGlobalRoot
    (outcome : FederationOutcomeKind) :
    ¬ CreatesGlobalRootAuthority outcome := by
  cases outcome <;> simp [CreatesGlobalRootAuthority]

theorem agreedFederationMayEnterLocalAdmission :
    MayEnterLocalFederationAdmission .agreed := by
  simp [MayEnterLocalFederationAdmission]

theorem candidateFederationFailsClosed :
    ¬ MayEnterLocalFederationAdmission .candidate := by
  simp [MayEnterLocalFederationAdmission]

theorem expiredFederationFailsClosed :
    ¬ MayEnterLocalFederationAdmission .expired := by
  simp [MayEnterLocalFederationAdmission]

theorem revokedFederationFailsClosed :
    ¬ MayEnterLocalFederationAdmission .revoked := by
  simp [MayEnterLocalFederationAdmission]

theorem ownershipTransferRequiresExactContractAndAuthority
    {DomainIdentity TransferContractIdentity AuthorityIdentity : Type}
    (attempt :
      OwnershipTransferAttempt
        DomainIdentity TransferContractIdentity AuthorityIdentity)
    (transferred : attempt.ownershipTransferred) :
    attempt.exactTransferContract ∧ attempt.transferAuthorityValid :=
  attempt.transferRequiresContractAndAuthority transferred

end PooFlowCoreProof.Admission.Federation
