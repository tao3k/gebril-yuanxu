-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PooFlowCoreProof.Admission.RouteMutation

namespace PooFlowCoreProof.Admission.ReplayOwnership

def quintSourceDigest : String := "sha256:43f2b3a84b19544d6b927b380b9454c94231464703c3f63616839f4138216917"

-- Native eq? identities project to Nat; each frame is built from authenticated
-- selected-read receivers. affected is the existing invalidation closure.
def guarded (frames : List (List Nat)) (affected : List Nat) : Prop :=
  ∃ frame ∈ frames, ∃ owner ∈ affected, owner ∈ frame

instance (frames : List (List Nat)) (affected : List Nat) : Decidable (guarded frames affected) := by
  unfold guarded
  infer_instance

def edit (frames : List (List Nat)) (affected : List Nat)
    (revisions : Nat → Nat) : Option (Nat → Nat) :=
  if guarded frames affected then none else
    some (fun owner => if owner ∈ affected then revisions owner + 1 else revisions owner)

theorem selected_write_refused (frames : List (List Nat)) (affected frame : List Nat)
    (owner : Nat) (revisions : Nat → Nat) (f : frame ∈ frames)
    (a : owner ∈ affected) (s : owner ∈ frame) :
    edit frames affected revisions = none := by
  simp [edit, guarded, show ∃ x ∈ frames, ∃ y ∈ affected, y ∈ x from ⟨frame, f, owner, a, s⟩]

theorem nested_frame_keeps_outer (outer : List (List Nat)) (inner frame : List Nat)
    (affected : List Nat) (owner : Nat) (revisions : Nat → Nat)
    (f : frame ∈ outer) (a : owner ∈ affected) (s : owner ∈ frame) :
    edit (inner :: outer) affected revisions = none := by
  exact selected_write_refused _ _ _ owner _ (List.mem_cons_of_mem _ f) a s

theorem rejected_edit_has_no_partial_clear (frames : List (List Nat))
    (affected : List Nat) (revisions : Nat → Nat) (h : guarded frames affected) :
    edit frames affected revisions = none := by simp [edit, h]

theorem independent_edit_allowed (frames : List (List Nat))
    (affected : List Nat) (revisions : Nat → Nat) (h : ¬ guarded frames affected) :
    (edit frames affected revisions).isSome = true := by simp [edit, h]

theorem unaffected_parent_unchanged (frames : List (List Nat)) (affected : List Nat)
    (revisions : Nat → Nat) (parent : Nat) (h : ¬ guarded frames affected)
    (p : parent ∉ affected) :
    (edit frames affected revisions).map (fun result => result parent) = some (revisions parent) := by
  simp [edit, h, p]

-- Dynamic parameter unwinding restores the caller's frame stack on BOTH
-- success and exceptional return. Compiler/runtime parameterize correctness
-- remains a premise, checked by independent native exception/nesting cases.
def returnFrame {ε α : Type} (outer : List (List Nat)) (outcome : Except ε α) :=
  (outer, outcome)

theorem exceptional_return_restores_outer {ε α : Type} (outer : List (List Nat)) (e : ε) :
    (returnFrame outer (Except.error e : Except ε α)).1 = outer := rfl

theorem exceptional_return_preserves_error {ε α : Type} (outer : List (List Nat)) (e : ε) :
    (returnFrame outer (Except.error e : Except ε α)).2 = Except.error e := rfl

-- A raw SDK field write does not enter edit; the RouteMutation roundtrip still
-- retains its side effect. The new frame cannot upgrade that trust boundary.
theorem raw_bypass_still_has_history (s : RouteMutation.RuntimeState) :
    (RouteMutation.roundTrip s).calls = s.calls + 1 := rfl

end PooFlowCoreProof.Admission.ReplayOwnership
