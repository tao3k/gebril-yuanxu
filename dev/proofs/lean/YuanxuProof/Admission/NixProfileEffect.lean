-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SerialUse

namespace YuanxuProof.Admission.NixProfileEffect

def quintSourceDigest : String :=
  "sha256:eee6ea72b7e6545a5287ba284289ec7390d12e101a390393748cf011c2d1ee1e"

structure Head where
  revision : Nat
  snapshot : Nat
  deriving DecidableEq

-- Projection of the actual --set boundary: no expected revision operand.
-- The counter is a model transition index, NOT a claim about Nix generation IDs.
def setSnapshot (target : Nat) (head : Head) : Head :=
  ⟨head.revision + 1, target⟩

theorem stale_request_is_not_refused (oldTarget newerTarget revision : Nat) :
    (setSnapshot oldTarget (setSnapshot newerTarget ⟨revision, oldTarget⟩)).snapshot =
      oldTarget := rfl

theorem target_aba_does_not_restore_revision (oldTarget newerTarget revision : Nat) :
    (setSnapshot oldTarget (setSnapshot newerTarget ⟨revision, oldTarget⟩)).revision =
      revision + 2 := by simp [setSnapshot, Nat.add_assoc]

-- Reuse the prior external-owner precondition relation. It describes the
-- missing adapter obligation, not an implemented Nix conditional option.
theorem conditional_adapter_would_refuse (revision : Nat) :
    SerialUse.conditionalCommit true revision (revision + 2) = false :=
  SerialUse.version_aba_refuses_commit true revision

def prepared (a b : Bool) : Bool := a && b

theorem preparation_retains_both (a b : Bool) (h : prepared a b = true) :
    a = true ∧ b = true := by simpa [prepared, Bool.and_eq_true] using h

-- sourceCurrent is deliberately not consulted by an already saved --set.
def savedEffect (_sourceCurrent : Bool) (target : Nat) (head : Head) : Head :=
  setSnapshot target head

theorem source_change_cannot_rewrite_snapshot (target : Nat) (head : Head) :
    (savedEffect false target head).snapshot = target := rfl

theorem child_switch_preserves_parent (parent target : Nat) (head : Head) :
    (parent, setSnapshot target head).1 = parent := rfl

end YuanxuProof.Admission.NixProfileEffect
