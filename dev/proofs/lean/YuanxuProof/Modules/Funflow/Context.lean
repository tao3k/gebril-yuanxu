-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Proof.Types
import LeanPoo.Functional.Assembly

namespace YuanxuProof.Modules.Funflow.Context

universe u

structure PureEvaluationContextPolicy
    (Capability Adapter Disclosure : Type u) where
  allowsCapability : Capability → Prop
  allowsAdapter : Adapter → Prop
  allowsDisclosure : Disclosure → Prop

structure LiveEvaluationContext
    (Capability Adapter Disclosure : Type u) where
  policy : PureEvaluationContextPolicy Capability Adapter Disclosure
  remainingBudget : Nat
  deadline : Nat
  remainingContinuations : Nat
  cancelled : Bool

structure ExecutionDemand
    (Capability Adapter Disclosure : Type u) where
  capability : Capability
  adapter : Adapter
  disclosure : Disclosure
  budgetCost : Nat
  completesBy : Nat
  continuationUses : Nat

structure Admitted
    {Capability Adapter Disclosure : Type u}
    (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure) : Prop where
  capabilityAllowed :
    context.policy.allowsCapability demand.capability
  adapterAllowed :
    context.policy.allowsAdapter demand.adapter
  disclosureAllowed :
    context.policy.allowsDisclosure demand.disclosure
  budgetAvailable :
    demand.budgetCost ≤ context.remainingBudget
  completesWithinDeadline :
    demand.completesBy ≤ context.deadline
  continuationsAvailable :
    demand.continuationUses ≤ context.remainingContinuations
  notCancelled :
    context.cancelled = false

/-- Mathematical context policy is explicit input. The current Funflow strategy
has capability checks; this checker does not assert that the native runner meters
all future budget/deadline/continuation coordinates. -/
def Checks (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure) : Prop :=
  context.policy.allowsCapability demand.capability ∧
  context.policy.allowsAdapter demand.adapter ∧
  context.policy.allowsDisclosure demand.disclosure ∧
  demand.budgetCost ≤ context.remainingBudget ∧ demand.completesBy ≤ context.deadline ∧
  demand.continuationUses ≤ context.remainingContinuations ∧ context.cancelled = false

theorem admitted_iff_checks (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure) : Admitted context demand ↔ Checks context demand := by
  constructor
  · intro valid
    exact ⟨valid.capabilityAllowed, valid.adapterAllowed, valid.disclosureAllowed, valid.budgetAvailable,
      valid.completesWithinDeadline, valid.continuationsAvailable, valid.notCancelled⟩
  · rintro ⟨capability, adapter, disclosure, budget, deadline, continuations, cancelled⟩
    exact ⟨capability, adapter, disclosure, budget, deadline, continuations, cancelled⟩

instance (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure)
    [DecidablePred context.policy.allowsCapability] [DecidablePred context.policy.allowsAdapter]
    [DecidablePred context.policy.allowsDisclosure] : Decidable (Admitted context demand) := by
  letI : Decidable (Checks context demand) := by unfold Checks; infer_instance
  exact decidable_of_iff (Checks context demand) (admitted_iff_checks context demand).symm

def admitDemand (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure)
    [DecidablePred context.policy.allowsCapability] [DecidablePred context.policy.allowsAdapter]
    [DecidablePred context.policy.allowsDisclosure] :
    Option { requested : ExecutionDemand Capability Adapter Disclosure // Admitted context requested } :=
  if valid : Admitted context demand then some ⟨demand, valid⟩ else none

theorem cancelled_demand_rejected (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure)
    [DecidablePred context.policy.allowsCapability] [DecidablePred context.policy.allowsAdapter]
    [DecidablePred context.policy.allowsDisclosure] (cancelled : context.cancelled = true) :
    admitDemand context demand = none := by
  have refused : ¬ Admitted context demand := fun valid => by
    have same := valid.notCancelled
    simp [cancelled] at same
  simp [admitDemand, refused]

/-- Attach the checked context predicate to the dependency's actual proof object.
No arbitrary proposition is stored by a caller as a new 'admitted' field. -/
def demandObligation (demand : ExecutionDemand Capability Adapter Disclosure) :
    LeanPoo.Proof.Obligation Unit (fun _ => LiveEvaluationContext Capability Adapter Disclosure) where
  dependencies := [()]
  holds := fun state => Admitted (state ()) demand
  stable := by
    intro before after same proof
    have equal := same () (by simp)
    simpa only [equal] using proof

def demandObject (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure) :
    LeanPoo.Proof.ProofObject Unit (fun _ => LiveEvaluationContext Capability Adapter Disclosure) :=
  ⟨fun _ => context, [demandObligation demand]⟩

theorem demand_certificate_exact (context : LiveEvaluationContext Capability Adapter Disclosure)
    (demand : ExecutionDemand Capability Adapter Disclosure) :
    LeanPoo.Proof.Certificate (demandObject context demand) ↔ Admitted context demand := by
  simp [LeanPoo.Proof.Certificate, demandObject, demandObligation]
end YuanxuProof.Modules.Funflow.Context
