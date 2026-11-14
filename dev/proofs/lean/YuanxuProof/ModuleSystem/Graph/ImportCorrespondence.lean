-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission
import YuanxuProof.Admission.Source
import Std.Data.HashSet.Lemmas

/-! The runtime reader produces a finite source-text observation list. Reuse the
public source-check model to supply the discovery model's currentness premise.
Runtime context/path projection and event completeness remain executable gates. -/
namespace YuanxuProof.ModuleSystem.Graph.ImportCorrespondence
open TestAdmission
open YuanxuProof.Admission.Source

inductive DirectoryChild where
  | missing
  | wrongKind
  | admitted
  deriving DecidableEq, Repr

-- The snapshot index owns membership. A hit still checks the live path type.
def checkedDirectoryChild (listed : Bool) (name : String)
    (directoryNow : String → Bool) : DirectoryChild :=
  if !listed then .missing
  else if directoryNow name then .admitted
  else .wrongKind

theorem indexed_directory_child_matches_snapshot (children : List String) (name : String)
    (directoryNow : String → Bool) :
    checkedDirectoryChild ((Std.HashSet.ofList children).contains name) name directoryNow =
      checkedDirectoryChild (children.contains name) name directoryNow := by
  rw [Std.HashSet.contains_ofList]

theorem indexed_directory_child_does_not_authorize_stale_path
    (children : List String) (name : String)
    (listed : children.contains name = true) (changed : directoryNow name = false) :
    checkedDirectoryChild ((Std.HashSet.ofList children).contains name) name directoryNow =
      .wrongKind := by
  rw [Std.HashSet.contains_ofList, listed]
  simp [checkedDirectoryChild, changed]

/-- A path walk already checked the terminal kind. The publication handoff
can consume that observation in a closed interval. A fresh observation is
still required at any later currentness boundary. -/
theorem closed_terminal_kind_handoff (directory : Bool) :
    (directory && directory) = directory := by
  cases directory <;> rfl

#guard
  let names := (List.range 10000).map toString
  let children := Std.HashSet.ofList names
  names.all children.contains && !children.contains "10000"

private theorem split_source_equality (expected chunk rest : List α) :
    (expected.take chunk.length = chunk ∧ expected.drop chunk.length = rest) ↔
      expected = chunk ++ rest := by
  constructor
  · intro ⟨head, tail⟩
    rw [← List.take_append_drop chunk.length expected, head, tail]
  · rintro rfl
    exact ⟨List.take_left, List.drop_left⟩

def decodeSourceChunks : List (Except Failure (List α)) → Except Failure (List α)
  | [] => .ok []
  | part :: rest => do
      let chunk ← part
      let suffix ← decodeSourceChunks rest
      pure (chunk ++ suffix)

-- The decoder reaches EOF or its first failure even after a mismatching
-- chunk. The equality check uses only the current chunk and offset.
def checkSourceChunks [DecidableEq α] (expected : List α) :
    List (Except Failure (List α)) → Except Failure Bool
  | [] => .ok (decide (expected = []))
  | part :: rest => do
      let chunk ← part
      let suffixMatches ← checkSourceChunks (expected.drop chunk.length) rest
      pure (decide (expected.take chunk.length = chunk) && suffixMatches)

theorem source_chunk_check_preserves_decode_result [DecidableEq α]
    (expected : List α) (parts : List (Except Failure (List α))) :
    checkSourceChunks expected parts =
      (decodeSourceChunks parts).map (fun decoded => decide (expected = decoded)) := by
  induction parts generalizing expected with
  | nil => rfl
  | cons part rest ih =>
    cases part with
    | error cause => rfl
    | ok chunk =>
      cases tail : decodeSourceChunks rest with
      | error cause =>
        simp [checkSourceChunks, decodeSourceChunks, Bind.bind, Except.bind, Except.map, ih, tail]
      | ok suffix =>
        have compared :
            (decide (expected.take chunk.length = chunk) &&
              decide (expected.drop chunk.length = suffix)) = decide (expected = chunk ++ suffix) := by
          apply Bool.eq_iff_iff.mpr
          simp [split_source_equality]
        simp [checkSourceChunks, decodeSourceChunks, Bind.bind, Except.bind, Except.map, ih, tail]
        exact congrArg (Except.ok : Bool → Except Failure Bool) compared

example : checkSourceChunks [1] [.ok [2], .error "decoder"] = .error "decoder" := rfl

-- The directory view and its supplied reader have no interpreter demand.
-- A native demand owns the same independent checks around actual loading.
def nativeReaderDemand {World Reader Failure : Type}
    (needed : Bool) (check : World → Except Failure Unit)
    (load : World → Except Failure (Reader × World)) (world : World) :
    Except Failure (Option Reader × World) :=
  if needed then do
    check world
    let (reader, after) ← load world
    check after
    pure (some reader, after)
  else .ok (none, world)

theorem namespace_does_not_demand_native_reader
    (check : World → Except Failure Unit) (load : World → Except Failure (Reader × World))
    (world : World) :
    nativeReaderDemand false check load world = .ok (none, world) := rfl

theorem native_reader_load_checks_actual_return_state
    (check : World → Except Failure Unit) (load : World → Except Failure (Reader × World))
    (before after : World) (reader : Reader) (reason : Failure)
    (entered : check before = .ok ()) (loaded : load before = .ok (reader, after))
    (denied : check after = .error reason) :
    nativeReaderDemand true check load before = .error reason := by
  simp [nativeReaderDemand, Bind.bind, Except.bind, entered, loaded, denied]

-- Context order is supplied by the completed runtime traversal. Resolve the
-- CURRENT input registry during consumption; no per-root transitive list or
-- previously projected registration is required to preserve this result.
def registeredInputs (contexts : List Context) (lookup : Context → Option Input) : List Input :=
  contexts.filterMap lookup

def streamRegistered (contexts : List Context) (lookup : Context → Option Input)
    (reversed : List Input) : List Input :=
  contexts.foldl (fun out context =>
    match lookup context with
    | none => out
    | some input => input :: out) reversed

-- The Core callback accumulates in reverse, then restores ordered inputs.
-- This proves result equality, not garbage collection or heap-size bounds.
theorem stream_registered_exact (contexts : List Context) (lookup : Context → Option Input)
    (reversed : List Input) :
    streamRegistered contexts lookup reversed =
      (registeredInputs contexts lookup).reverse ++ reversed := by
  induction contexts generalizing reversed with
  | nil => rfl
  | cons context rest ih =>
    cases found : lookup context with
    | none => simpa [streamRegistered, registeredInputs, found] using ih reversed
    | some input =>
      simpa [streamRegistered, registeredInputs, found, List.reverse_cons,
        List.append_assoc] using ih (input :: reversed)

-- Cutting a canonical SDK subtree is valid only when every omitted context
-- has no private-source registration. Equality of names is insufficient.
-- This preserves order and multiplicity, not merely set membership. Runtime
-- traversal completeness and independent SDK source guarding remain gates.
theorem private_projection_cut (contexts : List Context) (keep : Context → Bool)
    (lookup : Context → Option Input)
    (absent : ∀ context ∈ contexts, keep context = false → lookup context = none) :
    registeredInputs (contexts.filter keep) lookup = registeredInputs contexts lookup := by
  induction contexts with
  | nil => rfl
  | cons head tail ih =>
    have rest := ih (fun context member => absent context (by simp [member]))
    cases marked : keep head with
    | false =>
      have missing := absent head (by simp) marked
      simp [registeredInputs, marked, missing] at rest ⊢
      exact rest
    | true =>
      simp only [registeredInputs, List.filter_cons, marked, ↓reduceIte,
                 List.filterMap_cons] at rest ⊢
      rw [rest]

-- The absent-registration premise is necessary, not a cache optimization
-- inferred from a context's name. An omitted registered dependency changes
-- the exact result even when another selected dependency remains present.
#guard registeredInputs [1] (fun n : Nat => some n) !=
       registeredInputs [0, 1] (fun n : Nat => some n)
#guard registeredInputs [1] (fun n : Nat => if n == 0 then none else some n) ==
       registeredInputs [0, 1] (fun n : Nat => if n == 0 then none else some n)

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

-- Runtime guards distinguish absence from a directory/symlink/nonregular file.
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

theorem runtime_entry_exact (expected : Option String) (state : PathState) :
    entryAccepted expected state = true ↔ state = expectedState expected := by
  cases expected <;> cases state <;> simp [entryAccepted, expectedState]

def runtimeGuard (inputs : List (String × Option String)) (read : String → PathState) : Bool :=
  inputs.all (fun input => entryAccepted input.2 (read input.1))

-- Source bytes and the runtime public-name resolution are distinct premises.
-- This models the retained preparation, not a memoized successful admission.
def publicPreparationGuard (inputs : List (String × Option String))
    (read : String → PathState) (expected : String) (resolved : Option String) : Bool :=
  runtimeGuard inputs read && (resolved == some expected)

theorem public_resolution_change_refused (inputs : List (String × Option String))
    (read : String → PathState) (expected : String) (resolved : Option String)
    (changed : resolved ≠ some expected) :
    publicPreparationGuard inputs read expected resolved = false := by
  simp [publicPreparationGuard, changed]

-- Identical registrations add no source requirement in one unchanged pure
-- world. An effect still requires a fresh guard; no temporal law follows.
theorem repeated_registration_same_requirements (inputs : List (String × Option String))
    (read : String → PathState) :
    runtimeGuard (inputs ++ inputs) read = runtimeGuard inputs read := by
  simp [runtimeGuard, List.all_append]

-- Adjacent private lookups leave the same read function and requirements.
-- This law does NOT identify worlds separated by an import or a callback.
theorem adjacent_guard_collapse (inputs : List (String × Option String))
    (read : String → PathState) :
    (runtimeGuard inputs read && runtimeGuard inputs read) = runtimeGuard inputs read := by
  cases runtimeGuard inputs read <;> rfl

#guard runtimeGuard [("provider.nix", some "old")] (fun _ => .regular "old") == true
#guard runtimeGuard [("provider.nix", some "old")] (fun _ => .regular "new") == false

theorem runtime_guard_exact (inputs : List (String × Option String))
    (read : String → PathState) :
    runtimeGuard inputs read = true ↔ ∀ input ∈ inputs, read input.1 = expectedState input.2 := by
  simp only [runtimeGuard, List.all_eq_true, runtime_entry_exact]

theorem changed_kind_or_text_rejected (inputs : List (String × Option String))
    (read : String → PathState) (input : String × Option String)
    (present : input ∈ inputs) (changed : read input.1 ≠ expectedState input.2) :
    runtimeGuard inputs read ≠ true := by
  intro accepted
  exact changed ((runtime_guard_exact inputs read).mp accepted input present)

-- A retained inert projection never substitutes for the actual source guard.
-- The Scheme gate separately checks that evaluated publications are NOT reused.
def guardedPreparation (inputs : List (String × Option String))
    (projection : Projection) (read : String → PathState)
    (policyAccepted : Bool) : Option Projection :=
  if runtimeGuard inputs read = true ∧ policyAccepted = true then some projection else none

theorem preparation_hit_requires_current (inputs : List (String × Option String))
    (projection result : Projection) (read : String → PathState) (policyAccepted : Bool)
    (hit : guardedPreparation inputs projection read policyAccepted = some result) :
    ∀ input ∈ inputs, read input.1 = expectedState input.2 := by
  by_cases accepted : runtimeGuard inputs read = true ∧ policyAccepted = true
  · exact (runtime_guard_exact inputs read).mp accepted.1
  · simp [guardedPreparation, accepted] at hit

theorem preparation_hit_requires_fresh_policy (inputs : List (String × Option String))
    (projection result : Projection) (read : String → PathState) (policyAccepted : Bool)
    (hit : guardedPreparation inputs projection read policyAccepted = some result) :
    policyAccepted = true := by
  by_cases accepted : runtimeGuard inputs read = true ∧ policyAccepted = true
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

theorem runtime_guard_supplies_source_admission (state : Discovery String)
    (inputs : List (String × String)) (read : String → Option String)
    (complete : state.pending = [])
    (covered : ∀ path ∈ state.seen, ∃ text, (path, text) ∈ inputs)
    (checked : checkSources inputs read = true) :
    SourceAdmitted state (snapshot inputs) read := by
  refine ⟨complete, ?_, checked_texts_are_current inputs read checked⟩
  intro path present
  obtain ⟨text, recorded⟩ := covered path present
  exact ⟨some text, List.mem_map.mpr ⟨(path, text), recorded, rfl⟩⟩

theorem changed_source_rejects_runtime_guard (inputs : List (String × String))
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

def selectedReaderForms {Forms : Type} (deferred : Bool)
    (deferredForms eagerForms : Unit → Forms) : Forms :=
  if deferred then deferredForms () else eagerForms ()

theorem deferred_reader_does_not_demand_eager_forms {Forms : Type}
    (deferredForms leftEager rightEager : Unit → Forms) :
    selectedReaderForms true deferredForms leftEager =
      selectedReaderForms true deferredForms rightEager := rfl

theorem eager_reader_does_not_demand_deferred_forms {Forms : Type}
    (eagerForms leftDeferred rightDeferred : Unit → Forms) :
    selectedReaderForms false leftDeferred eagerForms =
      selectedReaderForms false rightDeferred eagerForms := rfl

end YuanxuProof.ModuleSystem.Graph.ImportCorrespondence
