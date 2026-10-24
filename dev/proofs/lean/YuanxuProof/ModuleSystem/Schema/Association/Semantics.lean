-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.ContextSlot
import LeanPoo.Functional.ContractConsequence

/-! Narrow reference semantics, not an implementation/proof of Scheme's DFS or
source authentication. Node/Check IDs represent stable identities within one
view; the native-to-model identity/parent projection is an explicit premise. -/
namespace YuanxuProof.ModuleSystem.Schema.Association
open LeanPoo.Functional.Requirements

abbrev Parents := Nat → List Nat

inductive Inherits (parents : Parents) : Nat → Nat → Prop where
  | self (node) : Inherits parents node node
  | step {node parent root} : parent ∈ parents node →
      Inherits parents parent root → Inherits parents node root

/-- Bounded reference enumeration, retaining roots even across a diamond.
This is deliberately not claimed to equal the Scheme visited-state algorithm. -/
def ancestors (parents : Parents) : Nat → Nat → List Nat
  | 0, node => [node]
  | fuel + 1, node => node :: (parents node).flatMap (ancestors parents fuel)

theorem ancestors_sound (parents : Parents) (fuel node root : Nat)
    (found : root ∈ ancestors parents fuel node) : Inherits parents node root := by
  induction fuel generalizing node with
  | zero =>
      simp only [ancestors, List.mem_singleton] at found
      subst root
      exact .self node
  | succ fuel ih =>
      simp only [ancestors, List.mem_cons, List.mem_flatMap] at found
      rcases found with same | ⟨parent, member, found⟩
      · subst root; exact .self node
      · exact .step member (ih parent found)

theorem ancestors_complete {parents : Parents} {node root : Nat}
    (path : Inherits parents node root) :
    ∃ fuel, root ∈ ancestors parents fuel node := by
  induction path with
  | self node => exact ⟨0, by simp [ancestors]⟩
  | @step node parent root member path ih =>
      obtain ⟨fuel, found⟩ := ih
      exact ⟨fuel + 1, by
        simp only [ancestors, List.mem_cons, List.mem_flatMap]
        exact Or.inr ⟨parent, member, found⟩⟩

structure Anchor where
  root : Nat
  contract : Nat
  sourceRevision : Nat
  policyRevision : Nat
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Repr

def associations (parents : Parents) (fuel node : Nat) (index : List Anchor) : List Anchor :=
  index.filter (fun anchor => decide (anchor.root ∈ ancestors parents fuel node))

theorem association_sound (parents : Parents) (fuel node : Nat) (index : List Anchor)
    (anchor : Anchor) (found : anchor ∈ associations parents fuel node index) :
    anchor ∈ index ∧ Inherits parents node anchor.root := by
  simp only [associations, List.mem_filter, decide_eq_true_eq] at found
  exact ⟨found.1, ancestors_sound parents fuel node anchor.root found.2⟩

theorem association_complete (parents : Parents) (node : Nat) (index : List Anchor)
    (anchor : Anchor) (declared : anchor ∈ index)
    (path : Inherits parents node anchor.root) :
    ∃ fuel, anchor ∈ associations parents fuel node index := by
  obtain ⟨fuel, found⟩ := ancestors_complete path
  exact ⟨fuel, by simp only [associations, List.mem_filter, decide_eq_true_eq]; exact ⟨declared, found⟩⟩

/-- Each direct parent's root remains applicable; no first-parent selection. -/
theorem derived_root_preserved (parents : Parents) (child base : Nat)
    (edge : base ∈ parents child) (index : List Anchor) (anchor : Anchor)
    (declared : anchor ∈ index) (inherited : Inherits parents base anchor.root) :
    ∃ fuel, anchor ∈ associations parents fuel child index :=
  association_complete parents child index anchor declared (.step edge inherited)

/-- Preserve all bindings even if two published contracts share an object root. -/
theorem shared_root_keeps_both (parents : Parents) (node : Nat) (index : List Anchor)
    (left right : Anchor) (a : left ∈ index) (b : right ∈ index)
    (same : left.root = right.root) (path : Inherits parents node left.root) :
    (∃ fuel, left ∈ associations parents fuel node index) ∧
    (∃ fuel, right ∈ associations parents fuel node index) := by
  exact ⟨association_complete parents node index left a path,
    association_complete parents node index right b (same ▸ path)⟩

/-- Actual native .+ immediate parents: RHS parents followed by the LHS value.
It does not add the RHS object's own identity. -/
def plusParents (base : Nat) (rightParents : List Nat) : List Nat := rightParents ++ [base]

theorem plus_keeps_left (base : Nat) (rightParents : List Nat) :
    base ∈ plusParents base rightParents := by simp [plusParents]

theorem plus_omits_right (base right : Nat) (rightParents : List Nat)
    (different : right ≠ base) (absent : right ∉ rightParents) :
    right ∉ plusParents base rightParents := by simp [plusParents, different, absent]

/-- Mandatory requirements include provider facts, not only ancestry facts. -/
def requirementGate (mandatory retained : List Nat) : Except (List Nat) Unit :=
  if mandatory.all (fun requirement => retained.contains requirement) then .ok ()
  else .error mandatory

theorem gate_accepts_iff (mandatory retained : List Nat) :
    requirementGate mandatory retained = .ok () ↔
      ∀ requirement ∈ mandatory, requirement ∈ retained := by
  simp [requirementGate, List.all_eq_true]

theorem accepted_keeps_right_requirement (mandatory retained : List Nat) (right : Nat)
    (required : right ∈ mandatory) (accepted : requirementGate mandatory retained = .ok ()) :
    right ∈ retained := (gate_accepts_iff mandatory retained).mp accepted right required

theorem missing_right_requirement_refused (mandatory retained : List Nat) (right : Nat)
    (required : right ∈ mandatory) (missing : right ∉ retained) :
    requirementGate mandatory retained = .error mandatory := by
  have fails : ¬ mandatory.all (fun requirement => retained.contains requirement) = true := by
    intro all
    have every := (List.all_eq_true).mp all right required
    exact missing (List.contains_iff_mem.mp every)
  unfold requirementGate
  split
  · rename_i all
    exact (fails all).elim
  · rfl

/-- Every successful boundary either retained this requirement, or omission
would force refusal. No claim that native .+ itself enforces the gate. -/
theorem right_requirement_preserved_or_refused (mandatory retained : List Nat) (right : Nat)
    (required : right ∈ mandatory) :
    right ∈ retained ∨ requirementGate mandatory retained = .error mandatory := by
  by_cases present : right ∈ retained
  · exact Or.inl present
  · exact Or.inr (missing_right_requirement_refused mandatory retained right required present)

/-- The integration checks both retention and actual modeled obligation results.
A retained name alone cannot stand in for a successful Contract check. -/
def compositionGate (mandatory retained : List Nat) (check : Nat → Bool) :
    Except (List Nat) Unit :=
  if mandatory.all (fun requirement => retained.contains requirement) && retained.all check
  then .ok () else .error mandatory

theorem composition_accepts_iff (mandatory retained : List Nat) (check : Nat → Bool) :
    compositionGate mandatory retained check = .ok () ↔
      (∀ requirement ∈ mandatory, requirement ∈ retained) ∧
      (∀ requirement ∈ retained, check requirement = true) := by
  simp [compositionGate, Bool.and_eq_true, List.all_eq_true]

theorem accepted_right_requirement_checked (mandatory retained : List Nat)
    (check : Nat → Bool) (right : Nat) (required : right ∈ mandatory)
    (accepted : compositionGate mandatory retained check = .ok ()) :
    right ∈ retained ∧ check right = true := by
  obtain ⟨kept, valid⟩ := (composition_accepts_iff mandatory retained check).mp accepted
  exact ⟨kept right required, valid right (kept right required)⟩

/-- Identity tokens include the configuration/source/contract/policy view.
The mapping must change whenever effective values or graph validity change. -/
structure View where
  receiver : Nat
  generation : Nat
  sourceRevision : Nat
  contractRevision : Nat
  policyRevision : Nat
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Repr

/-- Ordered identity list; names/count alone cannot establish equality. -/
abbrev CheckIDs := List Nat
abbrev PipelineValues := fun (_ : View) (_ : Unit) => CheckIDs

def finalFamily (effective : View → CheckIDs) :
    Certified (Value := PipelineValues) [()]
      (fun context data => data.1 = effective context) where
  factories := (effective, PUnit.unit)
  valid _ := rfl

abbrev PipelineCache (effective : View → CheckIDs) := ContextSlot (finalFamily effective)

def cachedChecks (effective : View → CheckIDs) (slot : PipelineCache effective) (context : View) : CheckIDs :=
  (slot.read context).1.val.1

theorem cached_checks_are_final (effective : View → CheckIDs)
    (slot : PipelineCache effective) (context : View) :
    cachedChecks effective slot context = effective context := by
  have aligned := ContextSlot.read_value slot context
  exact congrArg Prod.fst aligned

theorem parent_cache_misses_for_child (effective : View → CheckIDs)
    (slot : PipelineCache effective) (parent child : View)
    (data : Snapshot (finalFamily effective) parent)
    (retained : slot.retained = some ⟨parent, data⟩) (changed : parent ≠ child) :
    (slot.read child).2.2 = false := by
  apply (ContextSlot.read_miss slot child ?_).1
  intro previous previousData same
  rw [retained] at same
  have contexts : parent = previous := congrArg (fun pair => pair.1) (Option.some.inj same)
  exact contexts ▸ changed

def finalValueGate (effective : View → CheckIDs) (context : View) (actual : CheckIDs) : Bool :=
  decide (actual = effective context)

theorem cached_value_passes_final_gate (effective : View → CheckIDs)
    (slot : PipelineCache effective) (context : View) :
    finalValueGate effective context (cachedChecks effective slot context) = true := by
  simp [finalValueGate, cached_checks_are_final]

theorem stale_parent_value_refused (effective : View → CheckIDs) (parent child : View)
    (changed : effective parent ≠ effective child) :
    finalValueGate effective child (effective parent) = false := by
  simp [finalValueGate, changed]

/-- An actual logical consequence can reuse the certified family; arbitrary
changed Contract IDs do not establish this premise. -/
theorem consequence_keeps_factories (effective : View → CheckIDs)
    (next : ∀ context, Results PipelineValues context [()] → Prop)
    (derive : ∀ context data, data.1 = effective context → next context data) :
    ((finalFamily effective).entails next derive).factories =
      (finalFamily effective).factories := rfl

#print axioms association_complete
#print axioms derived_root_preserved
#print axioms right_requirement_preserved_or_refused
#print axioms accepted_right_requirement_checked
#print axioms cached_checks_are_final
#print axioms parent_cache_misses_for_child
#print axioms stale_parent_value_refused
end YuanxuProof.ModuleSystem.Schema.Association
