-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Constructor arguments are already values and are not rebound after capture.
Constant lexical slots and lazy initializers over their shared argument frame
retain the same payload identities. Removing initializer environments therefore
does NOT prove reclamation of arguments held by native read records. Native slot
lowering, MOP hooks, the collector and byte costs are outside this theorem. -/
namespace YuanxuProof.PooClos.CarrierCapture

def constantPayloads (fields : List (List α)) : List α := fields.flatten
def sharedInitializerPayloads (fields : List (List α)) : List α :=
  fields.flatMap (fun _ => fields.flatten)

theorem payload_membership_preserved (fields : List (List α)) (value : α) :
    value ∈ sharedInitializerPayloads fields ↔ value ∈ constantPayloads fields := by
  constructor
  · intro member
    obtain ⟨_, _, payload⟩ := List.mem_flatMap.mp member
    exact payload
  · intro member
    obtain ⟨field, present, _⟩ := List.mem_flatten.mp member
    exact List.mem_flatMap.mpr ⟨field, present, member⟩

-- The retention claim is about identity support, not list multiplicity/order.
-- A carrier retained by a read record still retains its declared payloads.
theorem retained_payload_not_reclaimed (fields : List (List α)) (value : α)
    (held : value ∈ sharedInitializerPayloads fields) :
    value ∈ constantPayloads fields :=
  (payload_membership_preserved fields value).mp held

-- Core receipt constructors reuse this value-storage law. Only already
-- completed arguments become constant fields. Late formulas and their actual
-- descriptor references are retained separately and must not be retargeted.
def receiptSupport (fields : List (List α)) (lateFormulaSupport : List α) : List α :=
  constantPayloads fields ++ lateFormulaSupport

theorem receipt_payload_and_late_support_preserved (fields : List (List α))
    (lateFormulaSupport : List α) (value : α) :
    value ∈ sharedInitializerPayloads fields ++ lateFormulaSupport ↔
      value ∈ receiptSupport fields lateFormulaSupport := by
  simp only [List.mem_append, receiptSupport, payload_membership_preserved]

-- A field edit on the returned receipt is not an edit to the argument captured
-- by the original contract-identity formula. This equation holds for every
-- descriptor-name function, including one changed after construction.
theorem late_formula_keeps_original_descriptor (names : α → β)
    (original replacement : α) :
    (fun (_publishedDescriptor : α) => names original) replacement = names original := rfl

end YuanxuProof.PooClos.CarrierCapture
