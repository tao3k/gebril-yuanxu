-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Proof.Types
import LeanPoo.Functional.ContractJoin

namespace YuanxuProof.ModuleSystem.Schema.Contracts

universe u

open LeanPoo.Functional.Requirements
open LeanPoo.Proof

/-- Scope admission composes runtime value checking with policy on that SAME
checked value. This is ordered function composition, not an approval cache. -/
def admitScopeValue {Input Checked Error : Type}
    (validate : Input → Except Error Checked)
    (policy : Checked → Except Error Unit) (input : Input) : Except Error Checked :=
  match validate input with
  | .error cause => .error cause
  | .ok checked => match policy checked with
    | .error cause => .error cause
    | .ok _ => .ok checked

theorem scopeAdmissionExactSubject {Input Checked Error : Type}
    (validate : Input → Except Error Checked) (policy : Checked → Except Error Unit)
    (input : Input) (output : Checked) :
    admitScopeValue validate policy input = .ok output ↔
      validate input = .ok output ∧ policy output = .ok () := by
  cases value : validate input with
  | error cause => simp [admitScopeValue, value]
  | ok checked =>
    by_cases same : checked = output
    · subst output
      cases decision : policy checked <;> simp [admitScopeValue, value, decision]
    · cases decision : policy checked <;> simp [admitScopeValue, value, decision, same]

theorem scopeValueRefusalStopsPolicy {Input Checked Error : Type}
    (validate : Input → Except Error Checked) (policy : Checked → Except Error Unit)
    (input : Input) (cause : Error) (refused : validate input = .error cause) :
    admitScopeValue validate policy input = .error cause := by
  simp [admitScopeValue, refused]

theorem scopePolicyRetainsBothRequirements {Input Checked Error : Type}
    (validate : Input → Except Error Checked) (policy : Checked → Except Error Unit)
    (left right : Checked → Prop)
    (requires : ∀ checked, policy checked = .ok () → left checked ∧ right checked)
    (input : Input) (output : Checked)
    (accepted : admitScopeValue validate policy input = .ok output) :
    left output ∧ right output :=
  requires output ((scopeAdmissionExactSubject validate policy input output).mp accepted).2

/-- Accumulate actual typed obligations on the same state, using the dependency's
proof object. A new obligation requires proof; it is never a set-membership flag. -/
theorem extensionPreservesState (object : ProofObject Key Value)
    (obligation : Obligation Key Value) :
    (object.withObligation obligation).state = object.state := rfl

theorem extensionRetainsAndChecksContracts (object : ProofObject Key Value)
    (existing : Certificate object) (obligation : Obligation Key Value)
    (checked : obligation.holds object.state) :
    Certificate (object.withObligation obligation) :=
  Certificate.withObligation object existing obligation checked

/-- Repeating an already owned contract changes neither the logical admission
condition nor the state; no second set/deduplication implementation is needed. -/
theorem repeatedObligationPreservesValidity (object : ProofObject Key Value)
    (obligation : Obligation Key Value) (owned : obligation ∈ object.obligations) :
    Certificate (object.withObligation obligation) ↔ Certificate object := by
  constructor
  · intro certificate candidate member
    exact certificate candidate (List.mem_append.mpr (Or.inl member))
  · intro certificate
    exact Certificate.withObligation object certificate obligation (certificate obligation owned)

/-- Same-family contract composition retains the exact factories and data.
Equal claim shapes are insufficient: conjoin requires actual function equality. -/
theorem accumulatedResultPreservesValues
    {Context Key : Type} {Value : Context → Key → Type} {keys : List Key}
    {Left Right : ∀ c, Results Value c keys → Prop}
    (left : Certified keys Left) (right : Certified keys Right)
    (same : left.factories = right.factories) (context : Context) :
    ((left.conjoin right same).build context).val = (left.build context).val := rfl

inductive Compatibility where
  | canonicallyCompatible
  | provenIncompatible (evidenceIdentity : Nat)
  | unknown
deriving Repr, DecidableEq

def IsCompositionConflict : Compatibility → Prop
  | Compatibility.provenIncompatible _ => True
  | Compatibility.canonicallyCompatible => False
  | Compatibility.unknown => False

theorem unknownCompatibilityIsNotConflict :
    ¬ IsCompositionConflict Compatibility.unknown := by
  intro conflict
  exact conflict

structure WeakeningAuthorization (Authority : Type u) where
  authority : Authority
  authorityIdentity : Nat
  decisionIdentity : Nat
deriving Repr, DecidableEq

structure AuthorizedWeakening
    (Key Authority : Type) (Value : Key → Type) where
  original : ProofObject Key Value
  weakened : ProofObject Key Value
  sameState : weakened.state = original.state
  authorization : WeakeningAuthorization Authority
  originalSemanticIdentity : Nat
  weakenedSemanticIdentity : Nat
  identityChanged :
    weakenedSemanticIdentity ≠ originalSemanticIdentity
  blameIdentity : Nat
  blameMatchesAuthority :
    blameIdentity = authorization.authorityIdentity

structure RemovedObligation
    {Key Authority : Type} {Value : Key → Type}
    (weakening : AuthorizedWeakening Key Authority Value)
    (obligation : LeanPoo.Proof.Obligation Key Value) : Prop where
  presentBefore : obligation ∈ weakening.original.obligations
  absentAfter : ¬ obligation ∈ weakening.weakened.obligations

inductive ContractFailure (Obligation : Type u) where
  | compositionConflict (evidenceIdentity : Nat)
  | valueViolation (obligation : Obligation)
deriving Repr, DecidableEq

theorem compositionConflictIsNotValueViolation
    {Obligation : Type u}
    (evidenceIdentity : Nat)
    (obligation : Obligation) :
    (ContractFailure.compositionConflict evidenceIdentity :
        ContractFailure Obligation) ≠
      ContractFailure.valueViolation obligation := by
  intro equality
  cases equality

end YuanxuProof.ModuleSystem.Schema.Contracts
