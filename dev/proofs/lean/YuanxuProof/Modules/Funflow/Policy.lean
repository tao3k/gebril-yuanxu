-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation

namespace YuanxuProof.Modules.Funflow.Policy
open LeanPoo.Functional

/-! `control-plane/{policy,strategy,runner-support/validation}.ss`.
Symbols are projected as strings. Registry lookup supplies the task capability
and routing bit; this model checks their use, not registry completeness. -/
structure Strategy where
  name : String
  capabilities : List String
  cachePolicy : String
  failurePolicy : String
  deriving Repr, DecidableEq

structure ExecutionPolicy extends Strategy where
  frontier : List Nat
  deriving Repr, DecidableEq

/-- Freeze precisely the strategy metadata at the requested frontier. -/
def snapshot (strategy : Strategy) : Factory (List Nat) (fun _ => ExecutionPolicy) :=
  Factory.map (fun frontier value => ⟨value, frontier⟩) (fun _ => strategy)

def allows (policy : ExecutionPolicy) (capability : String) : Bool :=
  policy.capabilities.contains capability

def cacheEnabled (policy : ExecutionPolicy) : Bool := policy.cachePolicy != "no-cache"

structure Task where
  capability : String
  adapterRouted : Bool
  locallyRunnable : Bool
  deriving Repr, DecidableEq

inductive Failure where
  | strategyCapability | adapterCapability | frontier
  deriving Repr, DecidableEq

/-- Preserve the runner's order: strategy check precedes adapter check;
non-adapter tasks do not require adapter support. -/
def validateTask (strategy : Strategy) (adapter : List String) (task : Task) : Except Failure Task :=
  if task.capability ∈ strategy.capabilities then
    if task.adapterRouted && !adapter.contains task.capability then .error .adapterCapability
    else .ok task
  else .error .strategyCapability

def validatePlan (strategy : Strategy) (adapter : List String) :=
  Validation.traverse (validateTask strategy adapter)

theorem validated_has_capability (s : Strategy) (a : List String) (t output : Task)
    (accepted : validateTask s a t = .ok output) :
    t.capability ∈ s.capabilities ∧ (t.adapterRouted = true → t.capability ∈ a) ∧ output = t := by
  unfold validateTask at accepted
  split at accepted
  · rename_i supported
    split at accepted
    · contradiction
    · rename_i routed
      simp only [Except.ok.injEq] at accepted
      refine ⟨supported, ?_, accepted.symm⟩
      intro yes
      simpa [yes] using routed
  · contradiction

theorem missing_strategy_rejected (s : Strategy) (a : List String) (t : Task)
    (missing : t.capability ∉ s.capabilities) :
    validateTask s a t = .error .strategyCapability := by simp [validateTask, missing]

theorem local_task_ignores_adapter (s : Strategy) (a : List String) (t : Task)
    (supported : t.capability ∈ s.capabilities) (localRoute : t.adapterRouted = false) :
    validateTask s a t = .ok t := by simp [validateTask, supported, localRoute]

/-- A batch cannot publish a successful prefix when a later node is rejected. -/
theorem plan_error_has_rejected_node (s : Strategy) (a : List String) (tasks : List Task) (e : Failure)
    (rejected : validatePlan s a tasks = .error e) :
    ∃ before task after values, tasks = before ++ task :: after ∧
      validatePlan s a before = .ok values ∧ validateTask s a task = .error e :=
  (Validation.traverse_error_iff _ _ _).mp rejected

def admitFrontier (s : Strategy) (frontier : List Nat) : Except Failure (List Nat) :=
  if "graph-frontier" ∈ s.capabilities then .ok frontier else .error .frontier

theorem frontier_requires_capability (s : Strategy) (frontier output : List Nat)
    (accepted : admitFrontier s frontier = .ok output) :
    "graph-frontier" ∈ s.capabilities ∧ output = frontier := by
  unfold admitFrontier at accepted
  split at accepted
  · exact ⟨by assumption, (Except.ok.inj accepted).symm⟩
  · contradiction

theorem snapshot_preserves_checks (s : Strategy) (frontier : List Nat) (capability : String) :
    allows (snapshot s frontier) capability = s.capabilities.contains capability ∧
    (snapshot s frontier).frontier = frontier := ⟨rfl, rfl⟩

#guard match validateTask ⟨"s", [], "no-cache", "fail-fast"⟩ [] ⟨"external", true, false⟩ with
  | .error .strategyCapability => true | _ => false
#guard match validateTask ⟨"s", ["external"], "no-cache", "fail-fast"⟩ [] ⟨"external", true, false⟩ with
  | .error .adapterCapability => true | _ => false
#guard (validateTask ⟨"s", ["pure"], "no-cache", "fail-fast"⟩ [] ⟨"pure", false, true⟩).toOption ==
  some ⟨"pure", false, true⟩
#guard (admitFrontier ⟨"s", [], "no-cache", "fail-fast"⟩ [1]).toOption == none
end YuanxuProof.Modules.Funflow.Policy
