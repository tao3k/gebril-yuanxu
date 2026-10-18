-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.PooClos.ProofBoundary

namespace PooFlowCoreProof.PooClos.ConservativeExtension

inductive NativeOutcome (Value Error : Type) where
  | value (result : Value)
  | failure (error : Error)
  | diverges
  deriving DecidableEq, Repr

inductive ExtendedOutcome (Value Error Control : Type) where
  | completed (native : NativeOutcome Value Error)
  | suspended (control : Control)
  | denied (control : Control)
  | cancelled (control : Control)
  deriving DecidableEq, Repr

def eraseControlAndEvidence
    {Value Error Control : Type} :
    ExtendedOutcome Value Error Control →
      Option (NativeOutcome Value Error)
  | .completed native => some native
  | .suspended _ => none
  | .denied _ => none
  | .cancelled _ => none

structure PlaneBoundary where
  controlSuppliesDomainValues : Prop
  controlDoesNotSupplyDomainValues : ¬ controlSuppliesDomainValues
  evidenceSuppliesDomainValues : Prop
  evidenceDoesNotSupplyDomainValues : ¬ evidenceSuppliesDomainValues
  evidenceBecomesImplicitProfileSlot : Prop
  evidenceIsNotImplicitProfileSlot : ¬ evidenceBecomesImplicitProfileSlot

structure AllowedCompletion (Value Error Control : Type) where
  nativeOutcome : NativeOutcome Value Error
  extendedOutcome : ExtendedOutcome Value Error Control
  erasurePreserved :
    eraseControlAndEvidence extendedOutcome = some nativeOutcome

structure NativeResultPreservation (Value Error : Type) where
  nativeValue : Value
  extendedValue : Value
  sameValue : extendedValue = nativeValue
  substitutedByControl : Prop
  noControlSubstitution : ¬ substitutedByControl

structure NativeFailurePreservation (Value Error : Type) where
  nativeError : Error
  contextualizedError : Error
  sameFailureMeaning : contextualizedError = nativeError
  convertedToValue : Prop
  noFailureToValueConversion : ¬ convertedToValue

structure BudgetRestriction where
  publishesPartialValue : Prop
  noPartialValue : ¬ publishesPartialValue
  publishesGuessedValue : Prop
  noGuessedValue : ¬ publishesGuessedValue
  fabricatesReplacementFailure : Prop
  noReplacementFailure : ¬ fabricatesReplacementFailure

structure ResumptionContext
    (Root Revision Generation Demand SelfSuper History : Type) where
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  selfSuper : SelfSuper
  history : History

structure ResumptionContinuity
    (Root Revision Generation Demand SelfSuper History : Type) where
  suspended :
    ResumptionContext Root Revision Generation Demand SelfSuper History
  resumed :
    ResumptionContext Root Revision Generation Demand SelfSuper History
  sameRoot : resumed.root = suspended.root
  sameRevision : resumed.revision = suspended.revision
  sameGeneration : resumed.generation = suspended.generation
  sameDemand : resumed.demand = suspended.demand
  sameSelfSuper : resumed.selfSuper = suspended.selfSuper
  sameHistory : resumed.history = suspended.history
  retargetsNewerRoot : Prop
  noRootRetargeting : ¬ retargetsNewerRoot

structure CacheEquivalence (Outcome : Type) where
  cachedOutcome : Outcome
  fullNativeReevaluation : Outcome
  semanticEquivalence : cachedOutcome = fullNativeReevaluation
  definesSecondFixedPoint : Prop
  noSecondFixedPoint : ¬ definesSecondFixedPoint

structure ObservationNonInterference where
  forcesAdditionalSlot : Prop
  noAdditionalSlotDemand : ¬ forcesAdditionalSlot
  changesFinalSelf : Prop
  finalSelfUnchanged : ¬ changesFinalSelf
  changesSuperChain : Prop
  superChainUnchanged : ¬ changesSuperChain
  insertsHiddenProfileContribution : Prop
  noHiddenContribution : ¬ insertsHiddenProfileContribution

structure SingleRootPreservation where
  rootInstantiationCount : Nat
  oneRoot : rootInstantiationCount = 1
  reinstantiatesForDebugging : Prop
  noDebugReinstantiation : ¬ reinstantiatesForDebugging
  createsNewRootOnCacheMiss : Prop
  noCacheMissRoot : ¬ createsNewRootOnCacheMiss

structure GovernanceBoundary where
  restrictsExecutionAuthority : Prop
  restrictionEstablished : restrictsExecutionAuthority
  substitutesDomainValue : Prop
  noDomainValueSubstitution : ¬ substitutesDomainValue
  decisionReceiptBecomesSlotOverride : Prop
  noReceiptSlotOverride : ¬ decisionReceiptBecomesSlotOverride

structure ContinuationBoundary where
  continuationIsProfileOperand : Prop
  notAProfileOperand : ¬ continuationIsProfileOperand
  injectsArbitraryRecoveryValue : Prop
  noArbitraryValueInjection : ¬ injectsArbitraryRecoveryValue
  recoveryProtocolExplicitlyNative : Prop
  nativeRecoveryProtocolEstablished : recoveryProtocolExplicitlyNative

structure SevenObligationClosure where
  nativeResultPreserved : Prop
  nativeFailurePreserved : Prop
  budgetOnlyRestricts : Prop
  resumptionContinuous : Prop
  cacheEquivalent : Prop
  observationNonInterfering : Prop
  singleRootPreserved : Prop
  obligationsEstablished :
    nativeResultPreserved ∧
      nativeFailurePreserved ∧
      budgetOnlyRestricts ∧
      resumptionContinuous ∧
      cacheEquivalent ∧
      observationNonInterfering ∧
      singleRootPreserved

theorem completedOutcomeErasesToNative
    {Value Error Control : Type}
    (native : NativeOutcome Value Error) :
    eraseControlAndEvidence
      (ExtendedOutcome.completed (Control := Control) native) =
      some native := by
  rfl

theorem suspendedOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.suspended (Value := Value) (Error := Error) control) =
      none := by
  rfl

theorem deniedOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.denied (Value := Value) (Error := Error) control) =
      none := by
  rfl

theorem cancelledOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.cancelled (Value := Value) (Error := Error) control) =
      none := by
  rfl

theorem resumptionPreservesRoot
    {Root Revision Generation Demand SelfSuper History : Type}
    (continuity :
      ResumptionContinuity
        Root Revision Generation Demand SelfSuper History) :
    continuity.resumed.root = continuity.suspended.root :=
  continuity.sameRoot

theorem resumptionPreservesDemand
    {Root Revision Generation Demand SelfSuper History : Type}
    (continuity :
      ResumptionContinuity
        Root Revision Generation Demand SelfSuper History) :
    continuity.resumed.demand = continuity.suspended.demand :=
  continuity.sameDemand

theorem observationPreservesSelfAndSuper
    (observation : ObservationNonInterference) :
    ¬ observation.changesFinalSelf ∧
      ¬ observation.changesSuperChain :=
  ⟨observation.finalSelfUnchanged, observation.superChainUnchanged⟩


end PooFlowCoreProof.PooClos.ConservativeExtension
