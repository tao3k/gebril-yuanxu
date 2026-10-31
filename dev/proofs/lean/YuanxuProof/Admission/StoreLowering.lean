-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.MetadataAllocation
import YuanxuProof.Admission.IdentityDFS

namespace YuanxuProof.Admission.StoreLowering

def quintSourceDigest : String := "sha256:39a415db6886b7f87f237750dcc9f517e70657bb74e559611aba235b013a07b3"

inductive Route where
  | generated | reflective | inlined
  | precompiledGenerated | precompiledReflective | precompiledInlined | unlowered
  deriving DecidableEq, Repr

def mediated : Route → Bool
  | .unlowered => false
  | _ => true

structure Result where
  writes : Nat
  forcedDuring : Nat
  parent : Nat
  hot : Nat
  cold : Nat
  deriving DecidableEq, Repr

def attempt (route : Route) (hasCarrier : Bool) : Result :=
  if mediated route && hasCarrier then ⟨0, 0, 5432, 5432, 5432⟩
  else ⟨2, 1, 5432, 5432, 5440⟩

theorem mediated_prewrite_refusal (route : Route) (h : mediated route = true) :
    (attempt route true).writes = 0 ∧ (attempt route true).forcedDuring = 0 := by
  simp [attempt, h]

theorem mediated_no_cold_poison (route : Route) (h : mediated route = true) :
    (attempt route true).cold = 5432 ∧ (attempt route true).parent = 5432 ∧
    (attempt route true).hot = 5432 := by simp [attempt, h]

theorem unlowered_retains_counterexample :
    (attempt .unlowered true).cold = 5440 := rfl

-- The native correspondence decoder checks these independently built callees.
-- This route classification does not itself certify arbitrary binary code.
theorem precompiled_callees_refuse :
    (attempt .precompiledGenerated true).writes = 0 ∧
    (attempt .precompiledReflective true).writes = 0 ∧
    (attempt .precompiledInlined true).writes = 0 := by decide

theorem precompiled_callees_preserve_cold :
    (attempt .precompiledGenerated true).cold = 5432 ∧
    (attempt .precompiledReflective true).cold = 5432 ∧
    (attempt .precompiledInlined true).cold = 5432 := by decide

-- This is an exact-operation projection; no desired purity/coverage Prop is
-- accepted as a field. Native compiler/callback domain closure remains a bridge.
def declarations : List (Nat × Nat) :=
  MetadataAllocation.allocate
    (MetadataAllocation.allocate
      (MetadataAllocation.allocate
        (MetadataAllocation.allocate [] 17 1) 17 4) 17 5) 17 6
def edges : IdentityDFS.Edges := fun owner => if owner == 1 then [2, 3] else []
def owners : List Nat :=
  (IdentityDFS.walk edges 12
    ⟨MetadataOwnership.owners declarations 17, ∅, []⟩).order
theorem fixture_owners_derived : owners = [6, 5, 4, 1, 2, 3] := by
  simp [owners, declarations, MetadataAllocation.allocate, MetadataOwnership.owners,
    IdentityDFS.walk, IdentityDFS.step, edges, Std.HashSet.contains_insert]
theorem direct_copies_are_required : 4 ∈ owners ∧ 5 ∈ owners ∧ 6 ∈ owners := by
  rw [fixture_owners_derived]
  decide

theorem missing_carrier_retains_counterexample (route : Route) :
    (attempt route false).cold = 5440 := by simp [attempt]

end YuanxuProof.Admission.StoreLowering
