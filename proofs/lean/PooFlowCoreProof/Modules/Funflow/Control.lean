-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.PooClos.Runtime

namespace PooFlowCoreProof.Modules.Funflow.Control

inductive TerminalEffect where
  | continue
  | suspend
  | deny
  | cancel
  deriving DecidableEq, Repr

inductive HandlerTransition where
  | normalReturn
  | noncontinuableBoundary
  deriving DecidableEq, Repr

def applyTerminalEffect : TerminalEffect → HandlerTransition
  | .continue => .normalReturn
  | .suspend => .noncontinuableBoundary
  | .deny => .noncontinuableBoundary
  | .cancel => .noncontinuableBoundary

structure ControlContextIdentity
    (Evaluator Process Thread Root Revision Generation Demand SafePoint
      DynamicContext IssuerWitness : Type) where
  evaluator : Evaluator
  process : Process
  thread : Thread
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  safePoint : SafePoint
  dynamicContext : DynamicContext
  issuerWitness : IssuerWitness

structure ControlCondition (Context ConditionIdentity Evidence : Type) where
  context : Context
  conditionIdentity : ConditionIdentity
  evidence : Evidence
  immutablePooObject : Prop
  immutabilityEstablished : immutablePooObject
  containsRawContinuation : Prop
  noRawContinuation : ¬ containsRawContinuation
  containsProfileResult : Prop
  noProfileResult : ¬ containsProfileResult
  acquiresAuthorityFromShape : Prop
  noShapeAuthority : ¬ acquiresAuthorityFromShape

structure ConditionExtension
    (Context ConditionIdentity BaseEvidence ExtendedEvidence : Type) where
  base : ControlCondition Context ConditionIdentity BaseEvidence
  extended : ControlCondition Context ConditionIdentity ExtendedEvidence
  preservesContext : extended.context = base.context
  preservesIdentity :
    extended.conditionIdentity = base.conditionIdentity
  addsOnlyPureEvidence : Prop
  pureEvidenceEstablished : addsOnlyPureEvidence
  weakensCapabilityRequirement : Prop
  noCapabilityWeakening : ¬ weakensCapabilityRequirement
  acquiresAuthority : Prop
  noAuthorityAcquisition : ¬ acquiresAuthority
  erasesToBaseObservation : Prop
  erasureEstablished : erasesToBaseObservation

structure ControlDecision
    (ConditionIdentity CapabilityWitness Evidence : Type) where
  conditionIdentity : ConditionIdentity
  capabilityWitness : CapabilityWitness
  evidence : Evidence
  effect : TerminalEffect
  immutablePooObject : Prop
  immutabilityEstablished : immutablePooObject
  containsSecondTerminalEffect : Prop
  exactlyOneEffect : ¬ containsSecondTerminalEffect
  containsProfileValue : Prop
  noProfileValue : ¬ containsProfileValue
  containsRawContinuation : Prop
  noRawContinuation : ¬ containsRawContinuation

structure DecisionAdmission
    (ConditionIdentity CapabilityWitness Evidence : Type) where
  decision :
    ControlDecision ConditionIdentity CapabilityWitness Evidence
  expectedConditionIdentity : ConditionIdentity
  identityMatches :
    decision.conditionIdentity = expectedConditionIdentity
  capabilityValid : Prop
  capabilityEstablished : capabilityValid
  capabilityLiveAndUnconsumed : Prop
  liveAuthorityEstablished : capabilityLiveAndUnconsumed
  terminalEffectAllowed : Prop
  effectPermissionEstablished : terminalEffectAllowed

def EffectConstraint := TerminalEffect → Prop

def Attenuates
    (parent child : EffectConstraint) : Prop :=
  ∀ effect, child effect → parent effect

structure ControlCapability
    (Context IssuerWitness RuntimeCell : Type) where
  context : Context
  issuerWitness : IssuerWitness
  runtimeCell : RuntimeCell
  allowedEffects : EffectConstraint
  immutablePooObject : Prop
  immutabilityEstablished : immutablePooObject
  authorityDerivedFromObjectShape : Prop
  noShapeAuthority : ¬ authorityDerivedFromObjectShape
  usesMutableGlobalRegistry : Prop
  noGlobalRegistry : ¬ usesMutableGlobalRegistry
  reusableAuthority : Prop
  oneShotAuthority : ¬ reusableAuthority

structure CapabilityExtension
    (Context IssuerWitness RuntimeCell : Type) where
  parent : ControlCapability Context IssuerWitness RuntimeCell
  child : ControlCapability Context IssuerWitness RuntimeCell
  attenuates : Attenuates parent.allowedEffects child.allowedEffects
  createsNewIssuerWitness : Prop
  noNewIssuerWitness : ¬ createsNewIssuerWitness
  removesRevocation : Prop
  revocationPreserved : ¬ removesRevocation
  lengthensExpiry : Prop
  expiryNotLengthened : ¬ lengthensExpiry
  relaxesIdentityFence : Prop
  fenceNotRelaxed : ¬ relaxesIdentityFence

structure HandlerBoundary where
  acknowledgmentReachesProfileDomain : Prop
  acknowledgmentDiscarded : ¬ acknowledgmentReachesProfileDomain
  arbitraryHandlerValueAccepted : Prop
  noArbitraryHandlerValue : ¬ arbitraryHandlerValueAccepted
  resumeReturnedAsLocalDecision : Prop
  resumeIsCoordinatorAdmission : ¬ resumeReturnedAsLocalDecision

structure ControlReceiptBoundary where
  immutableEvidence : Prop
  evidenceEstablished : immutableEvidence
  carriesLiveAuthority : Prop
  noLiveAuthority : ¬ carriesLiveAuthority
  becomesProfileSlot : Prop
  notProfileSlot : ¬ becomesProfileSlot
  changesTerminalEffect : Prop
  noTerminalEffectChange : ¬ changesTerminalEffect

structure AlgebraAdmissionClosure where
  fixedGerbilPooCallFormsRecorded : Prop
  threeFamiliesArePooObjects : Prop
  conditionExtensionPreservesFence : Prop
  effectsClosedAndExclusive : Prop
  resumeIsCoordinatorAdmission : Prop
  attenuationOnly : Prop
  noGlobalRegistry : Prop
  noHandlerValueInjection : Prop
  nonContinueFailsClosed : Prop
  traceMatchesMermaid : Prop
  priorRfcObligationsSatisfied : Prop

def ImplementationAdmitted
    (closure : AlgebraAdmissionClosure) : Prop :=
  closure.fixedGerbilPooCallFormsRecorded ∧
    closure.threeFamiliesArePooObjects ∧
    closure.conditionExtensionPreservesFence ∧
    closure.effectsClosedAndExclusive ∧
    closure.resumeIsCoordinatorAdmission ∧
    closure.attenuationOnly ∧
    closure.noGlobalRegistry ∧
    closure.noHandlerValueInjection ∧
    closure.nonContinueFailsClosed ∧
    closure.traceMatchesMermaid ∧
    closure.priorRfcObligationsSatisfied

theorem continueReturnsNormally :
    applyTerminalEffect .continue = .normalReturn := by
  rfl

theorem suspendUsesNoncontinuableBoundary :
    applyTerminalEffect .suspend = .noncontinuableBoundary := by
  rfl

theorem denyUsesNoncontinuableBoundary :
    applyTerminalEffect .deny = .noncontinuableBoundary := by
  rfl

theorem cancelUsesNoncontinuableBoundary :
    applyTerminalEffect .cancel = .noncontinuableBoundary := by
  rfl

theorem admittedDecisionHasLiveAuthority
    {ConditionIdentity CapabilityWitness Evidence : Type}
    (admission :
      DecisionAdmission ConditionIdentity CapabilityWitness Evidence) :
    admission.capabilityValid ∧
      admission.capabilityLiveAndUnconsumed ∧
      admission.terminalEffectAllowed :=
  ⟨admission.capabilityEstablished, admission.liveAuthorityEstablished,
    admission.effectPermissionEstablished⟩

theorem attenuationIsTransitive
    (parent middle child : EffectConstraint)
    (first : Attenuates parent middle)
    (second : Attenuates middle child) :
    Attenuates parent child := by
  intro effect admitted
  exact first effect (second effect admitted)

theorem missingGerbilPooCallFormsBlocksImplementation
    (closure : AlgebraAdmissionClosure)
    (missing : ¬ closure.fixedGerbilPooCallFormsRecorded) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing admitted.1

theorem missingClosedEffectProofBlocksImplementation
    (closure : AlgebraAdmissionClosure)
    (missing : ¬ closure.effectsClosedAndExclusive) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing admitted.2.2.2.1

theorem missingAttenuationProofBlocksImplementation
    (closure : AlgebraAdmissionClosure)
    (missing : ¬ closure.attenuationOnly) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing admitted.2.2.2.2.2.1

theorem missingPriorRfcClosureBlocksImplementation
    (closure : AlgebraAdmissionClosure)
    (missing : ¬ closure.priorRfcObligationsSatisfied) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing admitted.2.2.2.2.2.2.2.2.2.2

end PooFlowCoreProof.Modules.Funflow.Control
