-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.ContextPullback


namespace YuanxuProof.ModuleSystem.Schema.Demand


universe u

/-- Projected runtime coordinates remain outside the semantic demand key. -/
structure LiveEvaluationContext where
  capabilityTokenDigest : Nat
  cacheSnapshotDigest : Nat
  clockEpoch : Nat
  workerIdentity : Nat
  runtimeGeneration : Nat
  deriving Repr, DecidableEq

structure PureSlotDemand
    (SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u)
    where
  semanticTarget : SemanticTarget
  demandCausal : DemandCausal
  evidenceRequest : EvidenceRequest
  executionPolicy : ExecutionPolicy
deriving Repr, DecidableEq

def businessResultCacheKey
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (demand :
      PureSlotDemand
        SemanticTarget
        DemandCausal
        EvidenceRequest
        ExecutionPolicy) :
    SemanticTarget :=
  demand.semanticTarget

structure LiveDemandRequest
    (SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u)
    where
  demand :
    PureSlotDemand
      SemanticTarget
      DemandCausal
      EvidenceRequest
      ExecutionPolicy
  context : LiveEvaluationContext
deriving Repr, DecidableEq

def liveBusinessResultCacheKey
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (request :
      LiveDemandRequest
        SemanticTarget
        DemandCausal
        EvidenceRequest
        ExecutionPolicy) :
    SemanticTarget :=
  businessResultCacheKey request.demand

open LeanPoo.Functional.Requirements

/-- Causal/evidence/execution labels are outside this certified business family.
The factory family is indexed only by the complete semantic target. -/
theorem businessDemandReadsCertifiedTarget
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy Key : Type}
    [DecidableEq SemanticTarget] {Value : SemanticTarget → Key → Type}
    {keys : List Key} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (slot : ContextSlot ready)
    (demand : PureSlotDemand SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy) :
    (slot.readAlong businessResultCacheKey demand).1.val =
      build ready.factories demand.semanticTarget :=
  ContextSlot.readAlong_value slot businessResultCacheKey demand

theorem sameSemanticTargetSameBusinessResultCacheKey
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (left right :
      PureSlotDemand
        SemanticTarget
        DemandCausal
        EvidenceRequest
        ExecutionPolicy)
    (sameTarget : left.semanticTarget = right.semanticTarget) :
    businessResultCacheKey left =
      businessResultCacheKey right := by
  exact sameTarget

theorem causalIdentityCannotSplitBusinessResultCache
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (target : SemanticTarget)
    (leftCausal rightCausal : DemandCausal)
    (evidence : EvidenceRequest)
    (policy : ExecutionPolicy) :
    businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := leftCausal
           evidenceRequest := evidence
           executionPolicy := policy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) =
      businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := rightCausal
           evidenceRequest := evidence
           executionPolicy := policy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) := by
  rfl

theorem evidenceRequestCannotSplitBusinessResultCache
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (target : SemanticTarget)
    (causal : DemandCausal)
    (leftEvidence rightEvidence : EvidenceRequest)
    (policy : ExecutionPolicy) :
    businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := causal
           evidenceRequest := leftEvidence
           executionPolicy := policy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) =
      businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := causal
           evidenceRequest := rightEvidence
           executionPolicy := policy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) := by
  rfl

theorem executionPolicyCannotSplitBusinessResultCache
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (target : SemanticTarget)
    (causal : DemandCausal)
    (evidence : EvidenceRequest)
    (leftPolicy rightPolicy : ExecutionPolicy) :
    businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := causal
           evidenceRequest := evidence
           executionPolicy := leftPolicy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) =
      businessResultCacheKey
        ({ semanticTarget := target
           demandCausal := causal
           evidenceRequest := evidence
           executionPolicy := rightPolicy } :
          PureSlotDemand
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) := by
  rfl

theorem liveContextCannotSplitBusinessResultCache
    {SemanticTarget DemandCausal EvidenceRequest ExecutionPolicy : Type u}
    (demand :
      PureSlotDemand
        SemanticTarget
        DemandCausal
        EvidenceRequest
        ExecutionPolicy)
    (leftContext rightContext : LiveEvaluationContext) :
    liveBusinessResultCacheKey
        ({ demand := demand
           context := leftContext } :
          LiveDemandRequest
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) =
      liveBusinessResultCacheKey
        ({ demand := demand
           context := rightContext } :
          LiveDemandRequest
            SemanticTarget
            DemandCausal
            EvidenceRequest
            ExecutionPolicy) := by
  rfl

end YuanxuProof.ModuleSystem.Schema.Demand
