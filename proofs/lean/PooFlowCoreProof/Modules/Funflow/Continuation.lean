-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.PooClos.ConservativeExtension

namespace PooFlowCoreProof.Modules.Funflow.Continuation

inductive CapabilityState where
  | fresh
  | consumed
  deriving DecidableEq, Repr

def consumeOneShot : CapabilityState → Option CapabilityState
  | .fresh => some .consumed
  | .consumed => none

inductive ControlDecision where
  | continue
  | suspend
  | deny
  | cancel
  | resume
  deriving DecidableEq, Repr

inductive RejectionKind where
  | controlRejection
  | nativePooFailure
  deriving DecidableEq, Repr

structure SuspensionContext
    (Evaluator Process Root Revision Generation Demand DynamicContext : Type) where
  evaluator : Evaluator
  process : Process
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  dynamicContext : DynamicContext

structure LiveContinuationCapability
    (Evaluator Process Root Revision Generation Demand DynamicContext : Type) where
  context :
    SuspensionContext
      Evaluator Process Root Revision Generation Demand DynamicContext
  state : CapabilityState
  opaqueProcessLocal : Prop
  processLocalEstablished : opaqueProcessLocal
  serializable : Prop
  notSerializable : ¬ serializable
  cacheable : Prop
  notCacheable : ¬ cacheable
  remotelyDelegable : Prop
  notRemotelyDelegable : ¬ remotelyDelegable
  profileOperand : Prop
  notProfileOperand : ¬ profileOperand

structure PortableSuspensionDescriptor
    (Root Revision Generation Demand SafePoint EvaluatorRevision
      BudgetPosition ReplayReference AuthorityRequirement : Type) where
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  safePoint : SafePoint
  evaluatorRevision : EvaluatorRevision
  budgetPosition : BudgetPosition
  replayReference : ReplayReference
  authorityRequirement : AuthorityRequirement
  purePooControlValue : Prop
  purityEstablished : purePooControlValue
  containsCallableContinuation : Prop
  noCallableContinuation : ¬ containsCallableContinuation
  grantsResumptionAuthority : Prop
  descriptorGrantsNoAuthority : ¬ grantsResumptionAuthority

structure ResumptionCapability (Descriptor Principal Budget Target : Type) where
  descriptor : Descriptor
  principal : Principal
  additionalBudget : Budget
  target : Target
  state : CapabilityState
  expired : Prop
  notExpired : ¬ expired
  revoked : Prop
  notRevoked : ¬ revoked

structure SafePointBoundary where
  semanticDemandKnown : Prop
  demandEstablished : semanticDemandKnown
  immutableRootKnown : Prop
  rootEstablished : immutableRootKnown
  stableFrontier : Prop
  frontierEstablished : stableFrontier
  hasUnrecordedPartialProfileValue : Prop
  noPartialProfileValue : ¬ hasUnrecordedPartialProfileValue
  hasUnresolvedExternalEffect : Prop
  noUnresolvedExternalEffect : ¬ hasUnresolvedExternalEffect
  hasReplayOrCheckpoint : Prop
  replayOrCheckpointEstablished : hasReplayOrCheckpoint

structure FenceContinuity
    (Root Revision Generation Demand : Type) where
  suspendedRoot : Root
  resumedRoot : Root
  sameRoot : resumedRoot = suspendedRoot
  suspendedRevision : Revision
  resumedRevision : Revision
  sameRevision : resumedRevision = suspendedRevision
  suspendedGeneration : Generation
  resumedGeneration : Generation
  sameGeneration : resumedGeneration = suspendedGeneration
  suspendedDemand : Demand
  resumedDemand : Demand
  sameDemand : resumedDemand = suspendedDemand
  retargetsNewRoot : Prop
  noRootRetargeting : ¬ retargetsNewRoot

structure ContinuableConditionBoundary where
  communicatesControlDecision : Prop
  controlCommunicationEstablished : communicatesControlDecision
  injectsImplicitProfileValue : Prop
  noImplicitProfileValue : ¬ injectsImplicitProfileValue
  nativeRecoveryProtocolPresent : Prop
  recoveryValueAdmitted : Prop
  recoveryRequiresNativeProtocol :
    recoveryValueAdmitted → nativeRecoveryProtocolPresent

structure PortableReconstructionBoundary where
  restoresSameSemanticDemand : Prop
  semanticContinuityEstablished : restoresSameSemanticDemand
  preservesRawVmContinuationIdentity : Prop
  noRawContinuationIdentityPromise : ¬ preservesRawVmContinuationIdentity
  entersAdmittedSafePoint : Prop
  admittedSafePointEstablished : entersAdmittedSafePoint
  createsNewProcessLocalContext : Prop
  newLocalContextEstablished : createsNewProcessLocalContext

structure SideEffectFence where
  effectNotStarted : Prop
  admittedCommitOrAbortReceipt : Prop
  replayIsIdempotent : Prop
  unresolvedEffectHiddenInDescriptor : Prop
  noHiddenUnresolvedEffect : ¬ unresolvedEffectHiddenInDescriptor
  portableCrossingJustified :
    effectNotStarted ∨ admittedCommitOrAbortReceipt ∨ replayIsIdempotent

structure RemoteWorkerBoundary where
  receivesPureDemandEnvelope : Prop
  pureEnvelopeEstablished : receivesPureDemandEnvelope
  receivesLiveContinuation : Prop
  noLiveContinuation : ¬ receivesLiveContinuation
  receivesResumptionAuthority : Prop
  noResumptionAuthority : ¬ receivesResumptionAuthority
  receivesUnresolvedEffectContext : Prop
  noUnresolvedEffectContext : ¬ receivesUnresolvedEffectContext

structure EvidenceBoundary where
  recordsControlTransition : Prop
  recordingEstablished : recordsControlTransition
  invokesContinuation : Prop
  cannotInvokeContinuation : ¬ invokesContinuation
  grantsResumptionAuthority : Prop
  cannotGrantAuthority : ¬ grantsResumptionAuthority
  becomesProfileSlot : Prop
  notProfileSlot : ¬ becomesProfileSlot

theorem freshCapabilityConsumesExactlyOnce :
    consumeOneShot .fresh = some .consumed := by
  rfl

theorem consumedCapabilityCannotBeConsumedAgain :
    consumeOneShot .consumed = none := by
  rfl

theorem controlRejectionIsNotNativePooFailure :
    RejectionKind.controlRejection ≠ .nativePooFailure := by
  decide

theorem resumptionCapabilityMustBeLive
    {Descriptor Principal Budget Target : Type}
    (capability : ResumptionCapability Descriptor Principal Budget Target) :
    ¬ capability.expired ∧ ¬ capability.revoked :=
  ⟨capability.notExpired, capability.notRevoked⟩

theorem resumptionPreservesRoot
    {Root Revision Generation Demand : Type}
    (continuity : FenceContinuity Root Revision Generation Demand) :
    continuity.resumedRoot = continuity.suspendedRoot :=
  continuity.sameRoot

theorem resumptionPreservesDemand
    {Root Revision Generation Demand : Type}
    (continuity : FenceContinuity Root Revision Generation Demand) :
    continuity.resumedDemand = continuity.suspendedDemand :=
  continuity.sameDemand

theorem conditionCommunicatesControlNotProfileValue
    (condition : ContinuableConditionBoundary) :
    condition.communicatesControlDecision ∧
      ¬ condition.injectsImplicitProfileValue :=
  ⟨condition.controlCommunicationEstablished, condition.noImplicitProfileValue⟩

theorem recoveryValueRequiresNativeProtocol
    (condition : ContinuableConditionBoundary)
    (admitted : condition.recoveryValueAdmitted) :
    condition.nativeRecoveryProtocolPresent :=
  condition.recoveryRequiresNativeProtocol admitted

theorem remoteWorkerReceivesPureDemandOnly
    (worker : RemoteWorkerBoundary) :
    worker.receivesPureDemandEnvelope ∧
      ¬ worker.receivesLiveContinuation ∧
      ¬ worker.receivesResumptionAuthority ∧
      ¬ worker.receivesUnresolvedEffectContext :=
  ⟨worker.pureEnvelopeEstablished, worker.noLiveContinuation,
    worker.noResumptionAuthority, worker.noUnresolvedEffectContext⟩

theorem evidenceCannotExerciseControlAuthority
    (evidence : EvidenceBoundary) :
    ¬ evidence.invokesContinuation ∧
      ¬ evidence.grantsResumptionAuthority ∧
      ¬ evidence.becomesProfileSlot :=
  ⟨evidence.cannotInvokeContinuation, evidence.cannotGrantAuthority,
    evidence.notProfileSlot⟩

end PooFlowCoreProof.Modules.Funflow.Continuation
