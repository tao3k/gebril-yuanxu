-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReplayOwnership

namespace YuanxuProof.Admission.MetadataOwnership

-- Source digest inserted after the finite projection is finalized.
def quintSourceDigest : String := "sha256:d6a55955cedced26d8c69a8b62caa55236db280eef0c8461ec4886981a5fd890"

-- Runtime association is eq?-based. A metadata identity may have multiple owners.
-- Completeness of this projection is NOT implied by a checked gateway.
def owners (association : List (Nat × Nat)) (target : Nat) : List Nat :=
  (association.filter (fun entry => entry.1 == target)).map Prod.snd

def write (frames : List (List Nat)) (association : List (Nat × Nat))
    (target : Nat) (revisions : Nat → Nat) : Option (Nat → Nat) :=
  if owners association target = [] then none
  else ReplayOwnership.edit frames (owners association target) revisions

theorem unknown_refused (frames : List (List Nat)) (association : List (Nat × Nat))
    (target : Nat) (revisions : Nat → Nat) (h : owners association target = []) :
    write frames association target revisions = none := by simp [write, h]

theorem associated_selected_refused (frames : List (List Nat))
    (association : List (Nat × Nat)) (target owner : Nat) (frame : List Nat)
    (revisions : Nat → Nat) (f : frame ∈ frames)
    (a : owner ∈ owners association target) (s : owner ∈ frame) :
    write frames association target revisions = none := by
  unfold write
  split
  · rfl
  · exact ReplayOwnership.selected_write_refused _ _ _ owner _ f a s

theorem nested_keeps_outer (outer : List (List Nat)) (inner frame : List Nat)
    (association : List (Nat × Nat)) (target owner : Nat) (revisions : Nat → Nat)
    (f : frame ∈ outer) (a : owner ∈ owners association target) (s : owner ∈ frame) :
    write (inner :: outer) association target revisions = none := by
  exact associated_selected_refused _ _ _ owner _ _ (List.mem_cons_of_mem _ f) a s

-- Unmediated writes can preserve endpoint metadata and still execute callbacks.
theorem restored_raw_route_keeps_effect (s : RouteMutation.RuntimeState) :
    (RouteMutation.roundTrip s).observation = s.observation ∧
    (RouteMutation.roundTrip s).calls = s.calls + 1 := by
  exact ⟨RouteMutation.raw_restore_keeps_observation s, rfl⟩

end YuanxuProof.Admission.MetadataOwnership
