-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreBuildPublication
namespace YuanxuProof.Admission.CoreBuildHandoff

def quintSourceDigest : String := "sha256:c0abdbbe07cd7d9c487ca927be9691a2735c8a73c01121064e7533d5ec558c5d"

-- Projection of the retained parent result, NOT a deserialized disk issuer.
structure Issuance where
  selection : String
  artifact : String
  record : String
  deriving DecidableEq

def accept (parent child : Issuance) : Bool := decide (parent = child)

theorem accept_requires_exact_projection (parent child : Issuance)
    (h : accept parent child = true) : parent = child := by
  simpa [accept] using h

theorem joint_disk_replacement_refused (selection original changed : String)
    (h : original ≠ changed) :
    accept ⟨selection, original, original⟩ ⟨selection, changed, changed⟩ = false := by
  simp [accept, Issuance.mk.injEq, h]

theorem warm_handoff (parent : Issuance) : accept parent parent = true := by
  simp [accept]

def finish (entry final a b parentCurrent : Bool) : Bool :=
  entry && final && a && b && parentCurrent

theorem final_and_both_requirements (entry final a b parentCurrent : Bool)
    (h : finish entry final a b parentCurrent = true) :
    final = true ∧ a = true ∧ b = true ∧ parentCurrent = true := by
  simp only [finish, Bool.and_eq_true] at h
  exact ⟨h.1.1.1.2, h.1.1.2, h.1.2, h.2⟩

-- Installation is receiver-indexed: a child's issuance cannot update parent.
def install (registry : Nat → Option Issuance) (child : Nat) (value : Issuance) :=
  fun key => if key = child then some value else registry key

theorem parent_receiver_isolation (registry : Nat → Option Issuance)
    (parent child : Nat) (value : Issuance) (h : parent ≠ child) :
    install registry child value parent = registry parent := by
  simp [install, h]

-- Trusted parent/child executables and the OS-owned pipe are extraction
-- premises. These statements do not authenticate an arbitrary stdin stream.
end YuanxuProof.Admission.CoreBuildHandoff
