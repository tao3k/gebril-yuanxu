-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Projection

/-! One selected responsibility family. Names are demand IDs in a sealed final
receiver view, not global Contract IDs. Native extraction/projection fidelity
and arbitrary transitive discovery are not proved here. -/
namespace YuanxuProof.ModuleSystem.Schema.Association.Selection
open Projection

def required (fixed selected : List Nat) : List Nat := fixed ++ selected

def gate (fixed selected performed : List Nat) (contract candidate : Nat → Nat)
    (context : Nat) (receipts : Nat → Receipt) : Except (List Nat) Unit :=
  compositionGate (required fixed selected) performed
    (fun slot => receiptGate (contract slot) (candidate slot) context (receipts slot))

theorem discovery_exact (fixed selected : List Nat) (slot : Nat) :
    slot ∈ required fixed selected ↔ slot ∈ fixed ∨ slot ∈ selected := by
  simp [required]

theorem selected_receipt_checked (fixed selected performed : List Nat)
    (contract candidate : Nat → Nat) (context slot : Nat) (receipts : Nat → Receipt)
    (chosen : slot ∈ selected)
    (accepted : gate fixed selected performed contract candidate context receipts = .ok ()) :
    slot ∈ performed ∧
      receiptGate (contract slot) (candidate slot) context (receipts slot) = true := by
  exact accepted_right_requirement_checked _ performed _ slot
    (List.mem_append_right fixed chosen) accepted

theorem missing_selected_refused (fixed selected performed : List Nat)
    (contract candidate : Nat → Nat) (context slot : Nat) (receipts : Nat → Receipt)
    (chosen : slot ∈ selected) (missing : slot ∉ performed) :
    gate fixed selected performed contract candidate context receipts ≠ .ok () := by
  intro accepted
  exact missing (selected_receipt_checked fixed selected performed contract candidate
    context slot receipts chosen accepted).1

theorem unselected_not_discovered (fixed selected : List Nat) (slot : Nat)
    (notFixed : slot ∉ fixed) (notSelected : slot ∉ selected) :
    slot ∉ required fixed selected := by
  simp [required, notFixed, notSelected]

theorem accepted_candidate_is_final (fixed selected performed : List Nat)
    (contract candidate : Nat → Nat) (context slot : Nat) (receipts : Nat → Receipt)
    (chosen : slot ∈ selected)
    (accepted : gate fixed selected performed contract candidate context receipts = .ok ()) :
    (receipts slot).candidate = candidate slot ∧ (receipts slot).context = context := by
  have checked := (selected_receipt_checked fixed selected performed contract candidate
    context slot receipts chosen accepted).2
  exact (accepted_receipt_correlated (contract slot) (candidate slot) context _ checked).2

-- No completed-checks comes from the user; performed models internal work only.
example (contract candidate : Nat → Nat) (context : Nat) (receipts : Nat → Receipt) :
    gate [0] [1, 2] [0, 1] contract candidate context receipts ≠ .ok () := by
  apply missing_selected_refused [0] [1, 2] [0, 1] contract candidate context 2 receipts
  · decide
  · decide

example : 2 ∉ required [0] [1] := by decide

#print axioms discovery_exact
#print axioms selected_receipt_checked
#print axioms missing_selected_refused
#print axioms unselected_not_discovered
#print axioms accepted_candidate_is_final
end YuanxuProof.ModuleSystem.Schema.Association.Selection
