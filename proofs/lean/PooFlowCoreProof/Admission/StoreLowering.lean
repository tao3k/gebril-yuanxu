-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PooFlowCoreProof.Admission.MetadataAllocation

namespace PooFlowCoreProof.Admission.StoreLowering

def quintSourceDigest : String := "sha256:6a7232da8567eb3d717f81c4d8e2a1ef7f85d53223c41c8af23a084f27205586"

inductive Route where
  | generated | reflective | inlined | unlowered
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

def attempt (route : Route) (protected : Bool) : Result :=
  if mediated route && protected then ⟨0, 0, 5432, 5432, 5432⟩
  else ⟨2, 1, 5432, 5432, 5440⟩

theorem mediated_prewrite_refusal (route : Route) (h : mediated route = true) :
    (attempt route true).writes = 0 ∧ (attempt route true).forcedDuring = 0 := by
  simp [attempt, h]

theorem mediated_no_cold_poison (route : Route) (h : mediated route = true) :
    (attempt route true).cold = 5432 ∧ (attempt route true).parent = 5432 ∧
    (attempt route true).hot = 5432 := by simp [attempt, h]

theorem unlowered_retains_counterexample :
    (attempt .unlowered true).cold = 5440 := rfl

-- This is an exact-operation projection; no desired purity/coverage Prop is
-- accepted as a field. Native compiler/callback domain closure remains a bridge.
def owners : List Nat := [1, 2, 3, 4, 5, 6]
theorem direct_copies_are_required : 4 ∈ owners ∧ 5 ∈ owners ∧ 6 ∈ owners := by decide

theorem missing_carrier_retains_counterexample (route : Route) :
    (attempt route false).cold = 5440 := by simp [attempt]

end PooFlowCoreProof.Admission.StoreLowering
