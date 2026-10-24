-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CheckerOrigin

namespace YuanxuProof.Admission.MetadataRoute

def quintSourceDigest : String :=
  "sha256:c5b82118d79dca759a40dd20eb089581d7b3f1f8ac8bf6057725d7f4410be0a3"

-- Native identity 0 is extracted from the trusted, pinned factory baseline.
structure Route where
  ref : Nat
  instanceRef : Nat
  hash : Nat
  test : Nat
  backend : Nat
  deriving DecidableEq, Repr

def baseline : Route := ⟨0, 0, 0, 0, 0⟩
def gate (r : Route) : Bool :=
  r.ref == 0 && r.instanceRef == 0 && r.hash == 0 && r.test == 0 && r.backend == 0

theorem full_gate_covers_nested_lookup (r : Route) (h : gate r = true) :
    r.ref = 0 ∧ r.instanceRef = 0 ∧ r.hash = 0 ∧ r.test = 0 ∧ r.backend = 0 := by
  simpa [gate, Bool.and_eq_true, and_assoc] using h

theorem outer_ref_does_not_close_hash :
    (⟨0, 0, 1, 0, 0⟩ : Route).ref = 0 ∧ gate ⟨0, 0, 1, 0, 0⟩ = false := by decide

theorem reads_table_does_not_close_instance_table :
    (⟨0, 1, 0, 0, 0⟩ : Route).ref = 0 ∧ gate ⟨0, 1, 0, 0, 0⟩ = false := by decide

-- The closed direct call has no callback transition. A callback must not be
-- smuggled into this operation by interpreting a pointer comparison as a fence.
def directCheck (r : Route) (s : ReturnTail.Live) : ReturnTail.Live × Bool :=
  (s, gate r)

theorem closed_direct_call_preserves_state (r : Route) (s : ReturnTail.Live) :
    (directCheck r s).1 = s := rfl

theorem entry_only_can_become_stale :
    gate baseline = true ∧ gate ⟨1, 0, 0, 0, 0⟩ = false := by decide

theorem equal_endpoints_do_not_erase_history :
    gate baseline = true ∧ gate baseline = true ∧
    (ReturnTail.lateExternal ReturnTail.origin).external = 1 := by decide

-- This is the metadata projection used by the native cache-miss checker.
-- It intentionally contains no private issuer witness or issuance registry.
structure MissProjection where
  receiver : Nat
  revision : Nat
  instanceId : Nat
  key : Nat
  cacheAbsent : Bool
  deriving DecidableEq, Repr

theorem equal_miss_projection_gets_same_decision
    (accept : MissProjection → Bool) (genuine forged : MissProjection)
    (same : genuine = forged) : accept genuine = accept forged := congrArg accept same

theorem no_projection_only_issuer
    (accept : MissProjection → Bool) (genuine forged : MissProjection)
    (same : genuine = forged) (allowed : accept genuine = true) :
    accept forged ≠ false := by
  rw [← same, allowed]
  decide

def admissible (r : Route) (a b : Bool) (owner : Nat) : Bool :=
  gate r && a && b && (owner == 2)

theorem accepted_retains_requirements_and_child (r : Route) (a b : Bool) (owner : Nat)
    (h : admissible r a b owner = true) : a = true ∧ b = true ∧ owner = 2 := by
  simp only [admissible, Bool.and_eq_true, beq_iff_eq] at h
  exact ⟨h.1.1.2, h.1.2, h.2⟩

theorem earlier_source_diagnosis_preserved (g c : Bool) :
    CheckerOrigin.firstFault false g c = some 0 := rfl

end YuanxuProof.Admission.MetadataRoute
