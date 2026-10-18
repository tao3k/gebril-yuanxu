-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Modules.Funflow.Delegation

namespace PooFlowCoreProof.Admission.Isolation

open PooFlowCoreProof.Modules.Funflow.Delegation

inductive ResourceAdmissionKind where
  | admitted
  | queued
  | suspended
  | rejected
  deriving DecidableEq, Repr

def ConsumesExecutionResources : ResourceAdmissionKind → Prop
  | .admitted => True
  | .queued => False
  | .suspended => False
  | .rejected => False

def IsExplicitBackpressure : ResourceAdmissionKind → Prop
  | .admitted => False
  | .queued => True
  | .suspended => True
  | .rejected => True

structure HierarchicalResourceBudget
    (Scope Dimension : Type) where
  parentScope : Scope
  childScopes : List Scope
  parentCapacity : Dimension → Nat
  admittedChildAggregate : Dimension → Nat
  aggregateWithinParent :
    ∀ dimension,
      admittedChildAggregate dimension ≤ parentCapacity dimension

structure ReservationIsolation
    (Tenant Dimension : Type) where
  tenant : Tenant
  reserved : Dimension → Nat
  consumed : Dimension → Nat
  consumptionWithinReservation :
    ∀ dimension, consumed dimension ≤ reserved dimension

structure BoundedQueueAdmission
    (Demand QueueIdentity CapacitySnapshot : Type) where
  demand : Demand
  queueIdentity : QueueIdentity
  capacitySnapshot : CapacitySnapshot
  queueDepth : Nat
  queueBound : Nat
  bounded : queueDepth ≤ queueBound
  outcome : ResourceAdmissionKind
  queuedOutcomeRequiresBackpressure :
    outcome = .queued → IsExplicitBackpressure outcome

structure ConditionalFairness (Demand : Type) where
  demand : Demand
  continuouslyEligible : Prop
  finiteEligibleCompetition : Prop
  schedulerMakesProgress : Prop
  eventuallyScheduled : Prop
  fairnessGuarantee :
    continuouslyEligible →
      finiteEligibleCompetition →
      schedulerMakesProgress →
      eventuallyScheduled

structure SchedulingSemanticIsolation
    (SemanticResolution SchedulingDecision : Type) where
  semanticBeforeScheduling : SemanticResolution
  schedulingDecision : SchedulingDecision
  semanticAfterScheduling : SemanticResolution
  schedulingPreservesResolution :
    semanticAfterScheduling = semanticBeforeScheduling

structure PrioritySeparation
    (SlotContributionPriority RuntimeSchedulingPriority : Type) where
  slotContributionPriority : SlotContributionPriority
  runtimeSchedulingPriority : RuntimeSchedulingPriority
  semanticPriorityOwner : Prop
  runtimePriorityOwner : Prop
  ownersSeparated : semanticPriorityOwner ∧ runtimePriorityOwner

structure AdmissionSuspensionHandoff
    (DemandIdentity ObservationCut PolicyIdentity ResumeToken : Type) where
  outcome : ResourceAdmissionKind
  suspendedOutcome : outcome = .suspended
  suspension :
    PortableSuspension
      DemandIdentity ObservationCut PolicyIdentity ResumeToken

structure ResourceReleaseReceipt
    (Demand ResourceIdentity ReceiptIdentity : Type) where
  demand : Demand
  resourceIdentity : ResourceIdentity
  receiptIdentity : ReceiptIdentity
  released : Prop
  releaseEstablished : released
  remainsConsumed : Prop
  noRemainingConsumption : ¬ remainsConsumed

theorem admittedDemandConsumesResources :
    ConsumesExecutionResources .admitted := by
  simp [ConsumesExecutionResources]

theorem queuedDemandDoesNotConsumeExecutionResources :
    ¬ ConsumesExecutionResources .queued := by
  simp [ConsumesExecutionResources]

theorem suspendedDemandDoesNotConsumeExecutionResources :
    ¬ ConsumesExecutionResources .suspended := by
  simp [ConsumesExecutionResources]

theorem rejectedDemandDoesNotConsumeExecutionResources :
    ¬ ConsumesExecutionResources .rejected := by
  simp [ConsumesExecutionResources]

theorem queueIsExplicitBackpressure :
    IsExplicitBackpressure .queued := by
  simp [IsExplicitBackpressure]

theorem suspensionIsExplicitBackpressure :
    IsExplicitBackpressure .suspended := by
  simp [IsExplicitBackpressure]

theorem rejectionIsExplicitBackpressure :
    IsExplicitBackpressure .rejected := by
  simp [IsExplicitBackpressure]

theorem queuedOutcomeCarriesBackpressure
    {Demand QueueIdentity CapacitySnapshot : Type}
    (admission :
      BoundedQueueAdmission Demand QueueIdentity CapacitySnapshot)
    (queued : admission.outcome = .queued) :
    IsExplicitBackpressure admission.outcome :=
  admission.queuedOutcomeRequiresBackpressure queued

theorem fairnessRequiresEligibilityCompetitionAndProgress
    {Demand : Type}
    (fairness : ConditionalFairness Demand)
    (eligible : fairness.continuouslyEligible)
    (finiteCompetition : fairness.finiteEligibleCompetition)
    (progress : fairness.schedulerMakesProgress) :
    fairness.eventuallyScheduled :=
  fairness.fairnessGuarantee eligible finiteCompetition progress

theorem backpressureSuspensionCarriesPortableState
    {DemandIdentity ObservationCut PolicyIdentity ResumeToken : Type}
    (handoff :
      AdmissionSuspensionHandoff
        DemandIdentity ObservationCut PolicyIdentity ResumeToken) :
    ∃ suspension :
        PortableSuspension
          DemandIdentity ObservationCut PolicyIdentity ResumeToken,
      suspension = handoff.suspension := by
  exact ⟨handoff.suspension, rfl⟩


end PooFlowCoreProof.Admission.Isolation
