-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Requirements

/-! Reference laws for the proposed constructor and selected admission closure.
The fold below is a requirement-algebra encoding, not extra native allocations.
Actual constructor capture and dependency completeness remain premises. -/
namespace YuanxuProof.ModuleSystem.Schema.Association.Construction
open Requirements Projection

def capture (token : Nat) (inputs : List Trace) : Trace :=
  inputs.foldr (fun source rest => .plus token source rest) (.fresh token)

theorem capture_membership (index : Nat → List Nat) (token requirement : Nat)
    (inputs : List Trace) :
    requirement ∈ requirements index (capture token inputs) ↔
      requirement ∈ index token ∨
        ∃ source ∈ inputs, requirement ∈ requirements index source := by
  induction inputs with
  | nil => simp [capture, requirements]
  | cons first rest ih =>
      change requirement ∈
        (index token ++ requirements index first ++ requirements index (capture token rest)) ↔ _
      simp only [List.mem_append]
      rw [ih]
      constructor
      · intro found
        rcases found with (own | firstFound) | own | later
        · exact Or.inl own
        · exact Or.inr ⟨first, by simp, firstFound⟩
        · exact Or.inl own
        · obtain ⟨source, member, required⟩ := later
          exact Or.inr ⟨source, List.mem_cons_of_mem _ member, required⟩
      · intro found
        rcases found with own | ⟨source, member, required⟩
        · exact Or.inl (Or.inl own)
        · rcases List.mem_cons.mp member with same | later
          · subst source
            exact Or.inl (Or.inr required)
          · exact Or.inr (Or.inr ⟨source, later, required⟩)

theorem source_receipt_checked (index : Nat → List Nat)
    (token requirement candidate context : Nat) (parents sources : List Trace)
    (source : Trace) (member : source ∈ parents ++ sources)
    (required : requirement ∈ requirements index source)
    (retained : List Nat) (receipts : Nat → Receipt)
    (accepted : compositionGate
      (requirements index (capture token (parents ++ sources))) retained
      (fun contract => receiptGate contract candidate context (receipts contract)) = .ok ()) :
    requirement ∈ retained ∧
      receiptGate requirement candidate context (receipts requirement) = true := by
  apply accepted_right_requirement_checked _ retained _ requirement ?_ accepted
  exact (capture_membership index token requirement _).mpr
    (Or.inr ⟨source, member, required⟩)

/-- Demand IDs are scoped to one sealed view; callbacks resolve FINAL values. -/
def nestedGate (selected : List Nat) (contracts : Nat → List Nat)
    (candidate context : Nat → Nat) (receipts : Nat → Nat → Receipt) : Bool :=
  selected.all fun demand => (contracts demand).all fun contract =>
    receiptGate contract (candidate demand) (context demand) (receipts demand contract)

def Closed (selected : List Nat) (dependencies : Nat → List Nat) : Prop :=
  ∀ parent ∈ selected, ∀ child ∈ dependencies parent, child ∈ selected

theorem selected_receipt_checked (selected : List Nat) (contracts : Nat → List Nat)
    (candidate context : Nat → Nat) (receipts : Nat → Nat → Receipt)
    (demand contract : Nat) (member : demand ∈ selected)
    (required : contract ∈ contracts demand)
    (accepted : nestedGate selected contracts candidate context receipts = true) :
    receiptGate contract (candidate demand) (context demand) (receipts demand contract) = true := by
  exact (List.all_eq_true.mp (List.all_eq_true.mp accepted demand member)) contract required

theorem nested_dependency_checked (selected : List Nat) (dependencies contracts : Nat → List Nat)
    (candidate context : Nat → Nat) (receipts : Nat → Nat → Receipt)
    (closed : Closed selected dependencies) (parent child contract : Nat)
    (selectedParent : parent ∈ selected) (dependency : child ∈ dependencies parent)
    (required : contract ∈ contracts child)
    (accepted : nestedGate selected contracts candidate context receipts = true) :
    receiptGate contract (candidate child) (context child) (receipts child contract) = true := by
  exact selected_receipt_checked selected contracts candidate context receipts child contract
    (closed parent selectedParent child dependency) required accepted

theorem missing_dependency_not_closed (selected : List Nat) (dependencies : Nat → List Nat)
    (parent child : Nat) (selectedParent : parent ∈ selected)
    (dependency : child ∈ dependencies parent) (missing : child ∉ selected) :
    ¬ Closed selected dependencies := by
  intro closed
  exact missing (closed parent selectedParent child dependency)

-- A passing outer gate is NOT a certificate of selected dependency closure.
example (candidate context : Nat → Nat) (receipts : Nat → Nat → Receipt) :
    nestedGate [0] (fun demand => if demand = 1 then [7] else [])
      candidate context receipts = true := by
  simp [nestedGate]

example : ¬ Closed [0] (fun _ => [1]) := by
  apply missing_dependency_not_closed [0] (fun _ => [1]) 0 1 <;> decide

#print axioms capture_membership
#print axioms source_receipt_checked
#print axioms selected_receipt_checked
#print axioms nested_dependency_checked
#print axioms missing_dependency_not_closed
end YuanxuProof.ModuleSystem.Schema.Association.Construction
