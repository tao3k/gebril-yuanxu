-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ClosedTail

namespace YuanxuProof.Admission.CheckerOrigin

def quintSourceDigest : String :=
  "sha256:ea7777873af378dc52d97b1c1878eacdca6d6c556ca8417434793783e2904c24"

-- The producer identity is projected as 0. This is not procedure-effect inference.
structure Read where
  checker : Nat
  record : Nat
  registered : Nat
  deriving DecidableEq, Repr

def owned (r : Read) : Bool := r.checker == 0 && r.record == r.registered
def preflight (closure : List Read) : Bool := closure.all owned

theorem accepted_record_has_native_identity_and_owner (r : Read)
    (h : owned r = true) : r.checker = 0 ∧ r.record = r.registered := by
  simpa [owned, Bool.and_eq_true] using h

theorem closure_covers_every_dependency (closure : List Read)
    (h : preflight closure = true) (r : Read) (member : r ∈ closure) :
    owned r = true := by
  exact List.all_eq_true.mp h r member

theorem copied_identity_does_not_copy_ownership :
    owned ⟨0, 2, 1⟩ = false := by decide

theorem raw_table_write_defeats_issuance_claim :
    owned ⟨0, 2, 2⟩ = true := by decide

-- Exact pure projection of the audited kernel's three branches. These Bool
-- inputs stand for primitive metadata comparisons, not user purity assertions.
inductive Kind where
  | ordinary | bootstrap | cacheMiss
  deriving DecidableEq, Repr

structure Metadata where
  revisionMatches : Bool
  instanceMatches : Bool
  ownerMatches : Bool
  valueMatches : Bool
  anchorMatches : Bool
  cacheAbsent : Bool

def kernelCurrent (kind : Kind) (m : Metadata) : Bool :=
  m.revisionMatches && match kind with
  | .ordinary => m.instanceMatches && m.ownerMatches && m.valueMatches
  | .bootstrap => m.anchorMatches
  | .cacheMiss => m.instanceMatches && m.cacheAbsent

theorem bootstrap_currentness_does_not_imply_ownership :
    kernelCurrent .bootstrap ⟨true, true, false, true, true, true⟩ = true := by decide

theorem cache_miss_currentness_does_not_imply_ownership :
    kernelCurrent .cacheMiss ⟨true, true, false, true, true, true⟩ = true := by decide

-- Pure check execution is conditional on the primitive metadata projection.
-- No theorem here authenticates an arbitrary Scheme closure or writable table.
def execute (closure : List Read) (state : ReturnTail.Live)
    (checks : List Bool) : ReturnTail.Live × Bool :=
  (state, preflight closure && checks.all id)

theorem fixed_kernel_preserves_state (closure : List Read) (state : ReturnTail.Live)
    (checks : List Bool) : (execute closure state checks).1 = state := rfl

-- Fixed outer procedure identity does not constrain a mutable HashTable::ref.
-- This counterexample is excluded by the primitive-metadata premise above.
theorem fixed_identity_does_not_close_metadata_dispatch :
    owned ⟨0, 1, 1⟩ = true ∧
    (ReturnTail.lateExternal ReturnTail.origin).external = 1 := by decide

def admit (closure : List Read) (checks : List Bool)
    (a b : Bool) (owner : Nat) : Bool :=
  preflight closure && checks.all id && a && b && (owner == 2)

theorem accepted_retains_two_requirements_and_child (closure : List Read)
    (checks : List Bool) (a b : Bool) (owner : Nat)
    (h : admit closure checks a b owner = true) :
    a = true ∧ b = true ∧ owner = 2 := by
  simp only [admit, Bool.and_eq_true, beq_iff_eq] at h
  exact ⟨h.1.1.2, h.1.2, h.2⟩

-- Validation order remains source first; the gate does not invoke a forbidden
-- checker to discover what diagnosis its execution might have produced.
def firstFault (sourceOK gateOK checkOK : Bool) : Option Nat :=
  if !sourceOK then some 0 else if !gateOK then some 1 else
  if !checkOK then some 2 else none

theorem source_failure_precedes_gate_and_checker (g c : Bool) :
    firstFault false g c = some 0 := rfl

end YuanxuProof.Admission.CheckerOrigin
