-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.Retention

namespace PooFlowCoreProof.Admission.KeyLifecycle

inductive KeyStatusKind where
  | candidate
  | active
  | expired
  | revoked
  | retired
  deriving DecidableEq, Repr

def MayAuthorizeNewSignature : KeyStatusKind → Prop
  | .active => True
  | .candidate => False
  | .expired => False
  | .revoked => False
  | .retired => False

def KeyPossessionCarriesGovernanceAuthority : KeyStatusKind → Prop
  | .candidate => False
  | .active => False
  | .expired => False
  | .revoked => False
  | .retired => False

structure KeyBinding
    (PrincipalIdentity KeyIdentity PurposeIdentity ScopeIdentity
      AlgorithmIdentity TimeAuthorityIdentity BindingIdentity : Type) where
  principalIdentity : PrincipalIdentity
  keyIdentity : KeyIdentity
  purposeIdentity : PurposeIdentity
  scopeIdentity : ScopeIdentity
  algorithmIdentity : AlgorithmIdentity
  timeAuthorityIdentity : TimeAuthorityIdentity
  bindingIdentity : BindingIdentity

structure KeyUseChecks where
  bindingMatches : Prop
  purposeMatches : Prop
  scopeMatches : Prop
  validityIntervalHolds : Prop
  notRevokedAtUse : Prop
  algorithmAllowed : Prop
  trustPathValid : Prop

def KeyUseChecksHold (checks : KeyUseChecks) : Prop :=
  checks.bindingMatches ∧
    checks.purposeMatches ∧
    checks.scopeMatches ∧
    checks.validityIntervalHolds ∧
    checks.notRevokedAtUse ∧
    checks.algorithmAllowed ∧
    checks.trustPathValid

structure KeyUseReceipt
    (PrincipalIdentity KeyIdentity PurposeIdentity ScopeIdentity
      AlgorithmIdentity TimeAuthorityIdentity BindingIdentity
      ReceiptIdentity : Type) where
  binding :
    KeyBinding
      PrincipalIdentity KeyIdentity PurposeIdentity ScopeIdentity
      AlgorithmIdentity TimeAuthorityIdentity BindingIdentity
  checks : KeyUseChecks
  checksHold : KeyUseChecksHold checks
  receiptIdentity : ReceiptIdentity

structure KeyRotation
    (PrincipalIdentity KeyIdentity BindingIdentity RotationIdentity : Type) where
  principalIdentity : PrincipalIdentity
  predecessorKey : KeyIdentity
  successorKey : KeyIdentity
  keysDistinct : predecessorKey ≠ successorKey
  predecessorBinding : BindingIdentity
  successorBinding : BindingIdentity
  bindingsDistinct : predecessorBinding ≠ successorBinding
  rotationIdentity : RotationIdentity

structure SigningEncryptionSeparation
    (SigningKeyIdentity EncryptionKeyIdentity : Type) where
  signingKey : SigningKeyIdentity
  encryptionKey : EncryptionKeyIdentity
  rolesSeparated : Prop
  separationEstablished : rolesSeparated

structure KeyRevocationObservation
    (KeyIdentity ObservationIdentity RevocationIdentity : Type) where
  keyIdentity : KeyIdentity
  effectiveObservationIdentity : ObservationIdentity
  revocationIdentity : RevocationIdentity
  newUseAllowed : Prop
  revokedKeyCannotAuthorizeNewUse : ¬ newUseAllowed

structure HistoricalSignatureEvidence
    (ContentCommitment SignatureIdentity PrincipalIdentity KeyBindingIdentity
      AlgorithmIdentity SigningObservationIdentity TrustPolicyIdentity
      RevocationObservationIdentity : Type) where
  contentCommitment : ContentCommitment
  signatureIdentity : SignatureIdentity
  principalIdentity : PrincipalIdentity
  keyBindingIdentity : KeyBindingIdentity
  algorithmIdentity : AlgorithmIdentity
  signingObservationIdentity : SigningObservationIdentity
  trustPolicyIdentity : TrustPolicyIdentity
  revocationObservationIdentity : RevocationObservationIdentity
  verificationMaterialRetained : Prop
  retentionEstablished : verificationMaterialRetained

structure HistoricalVerificationDecision
    (SignatureIdentity DecisionIdentity : Type) where
  signatureIdentity : SignatureIdentity
  signingTimeBindingValid : Prop
  trustPolicyAdmits : Prop
  revocationPolicyAdmits : Prop
  algorithmVerificationAvailable : Prop
  allHistoricalChecks :
    signingTimeBindingValid ∧
      trustPolicyAdmits ∧
      revocationPolicyAdmits ∧
      algorithmVerificationAvailable
  decisionIdentity : DecisionIdentity

structure AlgorithmMigration
    (OldAlgorithmIdentity NewAlgorithmIdentity AttestationIdentity : Type) where
  oldAlgorithmIdentity : OldAlgorithmIdentity
  newAlgorithmIdentity : NewAlgorithmIdentity
  algorithmsDistinct : Prop
  distinctionEstablished : algorithmsDistinct
  newAttestationIdentity : AttestationIdentity
  rewritesHistoricalSignature : Prop
  preservesHistoricalSignature : ¬ rewritesHistoricalSignature

theorem activeKeyMayAuthorizeNewSignature :
    MayAuthorizeNewSignature .active := by
  simp [MayAuthorizeNewSignature]

theorem expiredKeyFailsClosedForNewSignature :
    ¬ MayAuthorizeNewSignature .expired := by
  simp [MayAuthorizeNewSignature]

theorem revokedKeyFailsClosedForNewSignature :
    ¬ MayAuthorizeNewSignature .revoked := by
  simp [MayAuthorizeNewSignature]

theorem activeKeyPossessionIsNotGovernanceAuthority :
    ¬ KeyPossessionCarriesGovernanceAuthority .active := by
  simp [KeyPossessionCarriesGovernanceAuthority]

end PooFlowCoreProof.Admission.KeyLifecycle
