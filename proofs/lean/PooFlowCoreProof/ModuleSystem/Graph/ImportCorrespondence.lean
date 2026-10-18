-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PooFlowCoreProof.ModuleSystem.Graph.TestAdmission
import PooFlowCoreProof.Admission.Source

/-! The native reader produces a finite source-text observation list. Reuse the
public source-check model to supply the discovery model's currentness premise.
Native context/path projection and event completeness remain executable gates. -/
namespace PooFlowCoreProof.ModuleSystem.Graph.ImportCorrespondence
open TestAdmission
open PooFlowCoreProof.Admission.Source

-- The reader caches the completed SDK context list, not its input-registration
-- projection. Newly registered inputs must be visible on the next consumption.
def registeredInputs (contexts : List Context) (lookup : Context → Option Input) : List Input :=
  contexts.filterMap lookup

theorem current_registration_is_never_omitted (contexts : List Context)
    (lookup : Context → Option Input) (context : Context) (input : Input)
    (discovered : context ∈ contexts) (registered : lookup context = some input) :
    input ∈ registeredInputs contexts lookup :=
  List.mem_filterMap.mpr ⟨context, discovered, registered⟩

theorem later_registration_is_visible (contexts : List Context)
    (before after : Context → Option Input) (context : Context) (input : Input)
    (discovered : context ∈ contexts) (_previouslyAbsent : before context = none)
    (nowPresent : after context = some input) :
    input ∈ registeredInputs contexts after :=
  current_registration_is_never_omitted contexts after context input discovered nowPresent

def snapshot (inputs : List (String × String)) : List (String × Option String) :=
  inputs.map (fun input => (input.1, some input.2))

-- Native guards distinguish absence from a directory/symlink/nonregular file.
-- Mapping both to Option.none would incorrectly authorize negative observations.
inductive PathState where
  | missing
  | regular (text : String)
  | nonregular
  deriving DecidableEq, BEq, Repr

def readable : PathState → Option String
  | .regular text => some text
  | _ => none

def entryAccepted : Option String → PathState → Bool
  | none, .missing => true
  | some expected, .regular actual => actual == expected
  | _, _ => false

theorem positive_entry_uses_public_text_check (expected : String) (state : PathState) :
    entryAccepted (some expected) state = (readable state == some expected) := by
  cases state <;> rfl

theorem nonregular_is_not_absence : entryAccepted none .nonregular = false := rfl

def expectedState : Option String → PathState
  | none => .missing
  | some text => .regular text

theorem native_entry_exact (expected : Option String) (state : PathState) :
    entryAccepted expected state = true ↔ state = expectedState expected := by
  cases expected <;> cases state <;> simp [entryAccepted, expectedState]

def nativeGuard (inputs : List (String × Option String)) (read : String → PathState) : Bool :=
  inputs.all (fun input => entryAccepted input.2 (read input.1))

-- Adjacent private lookups leave the same read function and requirements.
-- This law does NOT identify worlds separated by an import or a callback.
theorem adjacent_guard_collapse (inputs : List (String × Option String))
    (read : String → PathState) :
    (nativeGuard inputs read && nativeGuard inputs read) = nativeGuard inputs read := by
  cases nativeGuard inputs read <;> rfl

#guard nativeGuard [("provider.nix", some "old")] (fun _ => .regular "old") == true
#guard nativeGuard [("provider.nix", some "old")] (fun _ => .regular "new") == false

theorem native_guard_exact (inputs : List (String × Option String))
    (read : String → PathState) :
    nativeGuard inputs read = true ↔ ∀ input ∈ inputs, read input.1 = expectedState input.2 := by
  simp only [nativeGuard, List.all_eq_true, native_entry_exact]

theorem changed_kind_or_text_rejected (inputs : List (String × Option String))
    (read : String → PathState) (input : String × Option String)
    (present : input ∈ inputs) (changed : read input.1 ≠ expectedState input.2) :
    nativeGuard inputs read ≠ true := by
  intro accepted
  exact changed ((native_guard_exact inputs read).mp accepted input present)

-- A retained inert projection never substitutes for the actual source guard.
-- The Scheme gate separately checks that evaluated publications are NOT reused.
def guardedPreparation (inputs : List (String × Option String))
    (projection : Projection) (read : String → PathState)
    (policyAccepted : Bool) : Option Projection :=
  if nativeGuard inputs read = true ∧ policyAccepted = true then some projection else none

theorem preparation_hit_requires_current (inputs : List (String × Option String))
    (projection result : Projection) (read : String → PathState) (policyAccepted : Bool)
    (hit : guardedPreparation inputs projection read policyAccepted = some result) :
    ∀ input ∈ inputs, read input.1 = expectedState input.2 := by
  by_cases accepted : nativeGuard inputs read = true ∧ policyAccepted = true
  · exact (native_guard_exact inputs read).mp accepted.1
  · simp [guardedPreparation, accepted] at hit

theorem preparation_hit_requires_fresh_policy (inputs : List (String × Option String))
    (projection result : Projection) (read : String → PathState) (policyAccepted : Bool)
    (hit : guardedPreparation inputs projection read policyAccepted = some result) :
    policyAccepted = true := by
  by_cases accepted : nativeGuard inputs read = true ∧ policyAccepted = true
  · exact accepted.2
  · simp [guardedPreparation, accepted] at hit

theorem revoked_policy_refuses_retained_syntax (inputs : List (String × Option String))
    (projection : Projection) (read : String → PathState) :
    guardedPreparation inputs projection read false = none := by
  simp [guardedPreparation]

theorem changed_preparation_refused (inputs : List (String × Option String))
    (projection : Projection) (read : String → PathState) (policyAccepted : Bool)
    (input : String × Option String) (present : input ∈ inputs)
    (changed : read input.1 ≠ expectedState input.2) :
    guardedPreparation inputs projection read policyAccepted = none := by
  simp [guardedPreparation, changed_kind_or_text_rejected inputs read input present changed]

theorem checked_texts_are_current (inputs : List (String × String))
    (read : String → Option String) (checked : checkSources inputs read = true) :
    SourcesCurrent (snapshot inputs) read := by
  have certificate := (checkSources_certifies inputs read).mp checked
  intro entry member
  obtain ⟨input, present, same⟩ := List.mem_map.mp member
  subst entry
  exact certificate (sourceObligation inputs) (by simp [sourceObject]) input present

theorem native_guard_supplies_source_admission (state : Discovery String)
    (inputs : List (String × String)) (read : String → Option String)
    (complete : state.pending = [])
    (covered : ∀ path ∈ state.seen, ∃ text, (path, text) ∈ inputs)
    (checked : checkSources inputs read = true) :
    SourceAdmitted state (snapshot inputs) read := by
  refine ⟨complete, ?_, checked_texts_are_current inputs read checked⟩
  intro path present
  obtain ⟨text, recorded⟩ := covered path present
  exact ⟨some text, List.mem_map.mpr ⟨(path, text), recorded, rfl⟩⟩

theorem changed_source_rejects_native_guard (inputs : List (String × String))
    (read : String → Option String) (input : String × String)
    (present : input ∈ inputs) (changed : read input.1 ≠ some input.2) :
    checkSources inputs read ≠ true := by
  intro checked
  exact changedSourceCannotBeCertified inputs read input present changed
    ((checkSources_certifies inputs read).mp checked)

theorem return_guard_supplies_current_evidence (inputs : List (String × String))
    (before after : String → Option String)
    (accepted : admitSources inputs before after = true) :
    SourcesCurrent (snapshot inputs) after := by
  have certified := returnCheck_certifies inputs before after accepted
  exact checked_texts_are_current inputs after ((checkSources_certifies inputs after).mpr certified)

theorem two_revisions_of_one_path_cannot_both_pass
    (inputs : List (String × String)) (read : String → Option String)
    (path left right : String) (first : (path, left) ∈ inputs)
    (second : (path, right) ∈ inputs) (different : left ≠ right) :
    checkSources inputs read ≠ true := by
  intro checked
  have current := checked_texts_are_current inputs read checked
  have leftRead := current (path, some left) (List.mem_map.mpr ⟨(path, left), first, rfl⟩)
  have rightRead := current (path, some right) (List.mem_map.mpr ⟨(path, right), second, rfl⟩)
  exact different (Option.some.inj (leftRead.symm.trans rightRead))

end PooFlowCoreProof.ModuleSystem.Graph.ImportCorrespondence
