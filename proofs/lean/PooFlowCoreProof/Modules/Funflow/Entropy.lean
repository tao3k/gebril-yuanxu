-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Modules.Funflow.Observation

namespace PooFlowCoreProof.Modules.Funflow.Entropy

open PooFlowCoreProof.Admission.Cache

inductive EntropyInputKind where
  | deterministicNoEntropy
  | explicitSemanticEntropy
  | missingSemanticEntropy
  | implicitLiveRandomness
  deriving DecidableEq, Repr

def AdmitsPureDerivation : EntropyInputKind → Prop
  | .deterministicNoEntropy => True
  | .explicitSemanticEntropy => True
  | .missingSemanticEntropy => False
  | .implicitLiveRandomness => False

def RequiresEntropySuspension : EntropyInputKind → Prop
  | .deterministicNoEntropy => False
  | .explicitSemanticEntropy => False
  | .missingSemanticEntropy => True
  | .implicitLiveRandomness => False

structure SemanticEntropyObservation
    (EntropyIdentity EntropyMaterial ProvenanceIdentity : Type) where
  entropyIdentity : EntropyIdentity
  entropyMaterial : EntropyMaterial
  provenanceIdentity : ProvenanceIdentity
  immutableInput : Prop
  immutabilityEstablished : immutableInput

structure DeterministicDerivation
    (SemanticCutIdentity Result ResultIdentity : Type) where
  semanticCutIdentity : SemanticCutIdentity
  originalResult : Result
  replayResult : Result
  originalResultIdentity : ResultIdentity
  replayResultIdentity : ResultIdentity
  replayResultStable : replayResult = originalResult
  replayIdentityStable :
    replayResultIdentity = originalResultIdentity

structure SemanticEntropyDerivation
    (SemanticCutIdentity EntropyIdentity PurposeIdentity ResultIdentity : Type)
    where
  semanticCutIdentity : SemanticCutIdentity
  entropyIdentity : EntropyIdentity
  purposeIdentity : PurposeIdentity
  resultIdentity : ResultIdentity
  readsLiveRandomness : Prop
  noLiveRandomnessRead : ¬ readsLiveRandomness

structure OperationalRandomnessUse
    (OperationIdentity RandomnessReceiptIdentity : Type) where
  operationIdentity : OperationIdentity
  randomnessReceiptIdentity : RandomnessReceiptIdentity
  affectsSemanticResult : Prop
  doesNotAffectSemanticResult : ¬ affectsSemanticResult
  affectsSemanticCacheKey : Prop
  doesNotAffectSemanticCacheKey : ¬ affectsSemanticCacheKey

structure EntropyConflictQuarantine
    (SemanticKey ExpectedDigest ObservedDigest ConflictIdentity : Type) where
  conflict :
    DeterminismConflict
      SemanticKey ExpectedDigest ObservedDigest ConflictIdentity

theorem deterministicDerivationNeedsNoEntropy :
    AdmitsPureDerivation .deterministicNoEntropy := by
  simp [AdmitsPureDerivation]

theorem explicitSemanticEntropyAdmitsDerivation :
    AdmitsPureDerivation .explicitSemanticEntropy := by
  simp [AdmitsPureDerivation]

theorem missingSemanticEntropyFailsClosed :
    ¬ AdmitsPureDerivation .missingSemanticEntropy := by
  simp [AdmitsPureDerivation]

theorem missingSemanticEntropyRequiresSuspension :
    RequiresEntropySuspension .missingSemanticEntropy := by
  simp [RequiresEntropySuspension]

theorem implicitLiveRandomnessIsRejected :
    ¬ AdmitsPureDerivation .implicitLiveRandomness := by
  simp [AdmitsPureDerivation]

end PooFlowCoreProof.Modules.Funflow.Entropy
