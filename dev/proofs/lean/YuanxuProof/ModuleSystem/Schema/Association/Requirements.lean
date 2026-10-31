-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Projection

/-! Proposed construction provenance, not an implemented Scheme MOP hook.
The index is fixed for one authenticated publication/policy view. Tokens denote
construction identities, not slot names. Completeness of native event capture
is an explicit integration premise, not a consequence of these theorems. -/
namespace YuanxuProof.ModuleSystem.Schema.Association.Requirements
open Projection

inductive Trace where
  | fresh (token : Nat)
  | derive (token : Nat) (parent : Trace)
  | plus (token : Nat) (left right : Trace)

def requirements (index : Nat → List Nat) : Trace → List Nat
  | .fresh token => index token
  | .derive token parent => index token ++ requirements index parent
  | .plus token left right =>
      index token ++ requirements index left ++ requirements index right

theorem derive_preserves (index : Nat → List Nat) (token requirement : Nat)
    (parent : Trace) (required : requirement ∈ requirements index parent) :
    requirement ∈ requirements index (.derive token parent) := by
  exact List.mem_append_right _ required

theorem plus_right_complete (index : Nat → List Nat) (token requirement : Nat)
    (left right : Trace) (required : requirement ∈ requirements index right) :
    requirement ∈ requirements index (.plus token left right) := by
  exact List.mem_append_right _ required

theorem accepted_right_receipt (index : Nat → List Nat)
    (token requirement candidate context : Nat) (left right : Trace)
    (retained : List Nat) (receipts : Nat → Receipt)
    (required : requirement ∈ requirements index right)
    (accepted : compositionGate (requirements index (.plus token left right)) retained
      (fun contract => receiptGate contract candidate context (receipts contract)) = .ok ()) :
    requirement ∈ retained ∧
      receiptGate requirement candidate context (receipts requirement) = true := by
  exact accepted_right_requirement_checked _ retained _ requirement
    (plus_right_complete index token requirement left right required) accepted

#print axioms derive_preserves
#print axioms plus_right_complete
#print axioms accepted_right_receipt
end YuanxuProof.ModuleSystem.Schema.Association.Requirements
