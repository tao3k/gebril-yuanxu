-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Building.SelectedPackages
import YuanxuProof.Admission.TestMakeLayout

/-! 13.31 native-source-view refinement. Reuses existing path layout and exact
closure models. Canonical path components, input completeness, serial effects
and authentic Gerbil product observations are native bridge premises. No new
loader, compilation scheduler, hash-authentication claim or approval cache. -/
namespace YuanxuProof.ModuleSystem.Building.SourceView

/-- A compiled binding outside the declared source owner is not a veto of
native package-scoped source resolution. `eligible` models source form and confinement;
the actual source header identity is validated before runtime admission. -/
def sourceCandidate (eligible : String → Bool) (bound native : Option String) : Option String :=
  (bound.filter eligible).orElse (fun () => native.filter eligible)

theorem outside_binding_uses_native (eligible : String → Bool) (bound : String)
    (native : Option String) (outside : eligible bound = false) :
    sourceCandidate eligible (some bound) native = native.filter eligible := by
  simp [sourceCandidate, Option.filter, outside]

theorem owned_binding_preserved (eligible : String → Bool) (bound : String)
    (native : Option String) (owned : eligible bound = true) :
    sourceCandidate eligible (some bound) native = some bound := by
  simp [sourceCandidate, Option.filter, owned]

/-- Native compiler package nesting does not remove the enclosing kernel
capability already admitted by the source Context. Both candidates have passed
their own confinement/header checks. No ancestor search supplies candidates. -/
def declaredSource (packageSource kernel : Option String) : Option String :=
  packageSource.orElse (fun () => kernel)

theorem nested_package_miss_uses_admitted_kernel (kernel : Option String) :
    declaredSource none kernel = kernel := rfl

theorem local_source_preserves_owner (packageSource : String) (kernel : Option String) :
    declaredSource (some packageSource) kernel = some packageSource := rfl
open YuanxuProof.Admission.TestMakeLayout

/-- The role inventory is extracted from admitted publication inputs. The Make
descriptor is not a second source for an ordinary Entry. Scheme must establish
that native import of the original path returns that path's canonical context. -/
def compilerPath (rolePaths : List String) (frame : String)
    (entry : Inputs.Entry) : String :=
  if entry.path ∈ rolePaths then frame else entry.path

theorem ordinary_path_preserved (rolePaths : List String) (frame : String)
    (entry : Inputs.Entry) (ordinary : entry.path ∉ rolePaths) :
    compilerPath rolePaths frame entry = entry.path := by
  simp [compilerPath, ordinary]

theorem admitted_role_uses_frame (rolePaths : List String) (frame : String)
    (entry : Inputs.Entry) (role : entry.path ∈ rolePaths) :
    compilerPath rolePaths frame entry = frame := by
  simp [compilerPath, role]

/-- Components are already admitted native compiler identity components. -/
def target (identity : List String) : Target := ⟨false, identity⟩

/-- Native std/make prefix/ distinguishes #f from the truthy empty string.
Generated views require an ABSENT prefix, with no package-prefix fallback. -/
def makePrefix (packagePrefix : Option String) (identity : String) : String :=
  match packagePrefix with | none => identity | some value => value ++ "/" ++ identity

theorem absent_prefix_preserves_identity (identity : String) : makePrefix none identity = identity := rfl

example : makePrefix (some "") "lab/module" = "/lab/module" := rfl
#guard makePrefix (some "") "lab/module" != makePrefix none "lab/module"

theorem unified_output_matches_identity (libdir identity : List String) :
    resolve libdir (target identity) = libdir ++ identity := rfl

theorem distinct_dynamic_targets (libdir left right : List String) (different : left ≠ right) :
    resolve libdir (target left) ≠ resolve libdir (target right) := by
  simpa [resolve, target] using different

/-- Generated view input data is restricted to the current selection. Native
ownership/regular-file checks precede deletion; no unowned file is adopted. -/
def pruneView (wanted previous : List String) : List String :=
  previous.filter (fun identity => wanted.contains identity)

theorem pruned_view_has_no_unselected_fallback (wanted previous : List String)
    (identity : String) (member : identity ∈ pruneView wanted previous) : identity ∈ wanted := by
  simpa using (List.mem_filter.mp member).2

theorem pruning_preserves_current_input (wanted previous : List String) (identity : String)
    (selected : identity ∈ wanted) (present : identity ∈ previous) :
    identity ∈ pruneView wanted previous := by
  simp [pruneView, selected, present]

/-- std/make static-path flattens identity separators. This encoding is NOT
injective; the physical output inventory needs its own collision check. -/
def staticStem (identity : List String) : String := String.intercalate "__" identity

def disjointOutputs (identities : List (List String)) : Bool :=
  identities.all (fun left => identities.all
    (fun right => decide (left = right) || staticStem left != staticStem right))

theorem accepted_static_outputs_injective (identities : List (List String))
    (checked : disjointOutputs identities = true) (left right : List String)
    (l : left ∈ identities) (r : right ∈ identities)
    (sameOutput : staticStem left = staticStem right) : left = right := by
  have row := List.all_eq_true.mp (List.all_eq_true.mp checked left l) right r
  simpa [sameOutput] using row

example : staticStem ["a", "b__c"] = staticStem ["a__b", "c"] := by rfl
#guard !disjointOutputs [["a", "b__c"], ["a__b", "c"]]
#guard disjointOutputs [["lab", "nix", "interface"], ["community", "helper"]]

/-- Persisted compiler-input data, not an approval. Actual source bytes and
negative package observations belong here, as do options/forms/toolchain. A
native implementation can derive this from existing prepared input snapshots. -/
structure Stamp where
  observations : List (String × Option String)
  options : List String
  forms : List String
  toolchain : String
  platform : String
  deriving DecidableEq, Repr

inductive DescriptorAction where
  | leaveNative
  | retireBeforeBuild
  | compareAndRecord
  deriving DecidableEq

/-- Ordinary Make can retain its own marker. A selected consumer needs the
exact shared view, and the source-only Prelude route grants no such record. -/
def descriptorAction (localBuild sourcePrelude previous marker : Bool) : DescriptorAction :=
  if localBuild && sourcePrelude then
    if previous then .retireBeforeBuild else .leaveNative
  else if !localBuild || previous || !marker then .compareAndRecord
  else .leaveNative

theorem local_source_prelude_issues_no_descriptor (previous marker : Bool) :
    descriptorAction true true previous marker ≠ .compareAndRecord := by
  cases previous <;> simp [descriptorAction]

theorem source_route_retires_an_old_descriptor (marker : Bool) :
    descriptorAction true true true marker = .retireBeforeBuild := rfl

theorem warm_local_marker_stays_with_make :
    descriptorAction true false false true = .leaveNative := rfl

theorem selected_consumer_requires_a_descriptor (sourcePrelude previous marker : Bool) :
    descriptorAction false sourcePrelude previous marker = .compareAndRecord := rfl

structure UnitState where
  descriptor : Stamp
  productInput : Option Stamp
  makeMarker : Bool
  deriving DecidableEq, Repr

/-- A marker is ordinary native completion, not signed publication. This
conditional invariant requires a trusted producer observation for productInput. -/
def Corresponds (state : UnitState) : Prop :=
  state.makeMarker = true → state.productInput = some state.descriptor

def invalidate (next : Stamp) (state : UnitState) : UnitState :=
  if state.descriptor = next then state else { state with makeMarker := false }

def writeDescriptor (next : Stamp) (state : UnitState) : UnitState :=
  { state with descriptor := next }

def prepareView (next : Stamp) (state : UnitState) : UnitState :=
  writeDescriptor next (invalidate next state)

/-- Success observation of the existing native compiler, not permission for
the adapter to manufacture a completion marker or suppress compiler failure. -/
def observeNativeSuccess (state : UnitState) : UnitState :=
  { state with productInput := some state.descriptor, makeMarker := true }

theorem invalidation_preserves_correspondence (next : Stamp) (state : UnitState)
    (current : Corresponds state) : Corresponds (invalidate next state) := by
  unfold invalidate
  split
  · exact current
  · simp [Corresponds]

theorem invalidation_before_descriptor_is_safe (next : Stamp) (state : UnitState)
    (current : Corresponds state) : Corresponds (prepareView next state) := by
  unfold prepareView invalidate
  split
  · rename_i same
    simpa [writeDescriptor, ← same] using current
  · simp [writeDescriptor, Corresponds]

theorem changed_stamp_loses_marker (next : Stamp) (state : UnitState)
    (changed : state.descriptor ≠ next) : (prepareView next state).makeMarker = false := by
  simp [prepareView, invalidate, changed, writeDescriptor]

theorem unchanged_stamp_preserves_state (state : UnitState) :
    prepareView state.descriptor state = state := by
  simp [prepareView, invalidate, writeDescriptor]

/-- Retrying a prepared input is idempotent; it does not observe compiler
success or manufacture a completion marker after a callback exception. -/
theorem preparation_idempotent (next : Stamp) (state : UnitState) :
    prepareView next (prepareView next state) = prepareView next state := by
  unfold prepareView invalidate writeDescriptor
  split <;> simp_all

theorem interrupted_retry_still_requires_native (next : Stamp) (state : UnitState)
    (changed : state.descriptor ≠ next) :
    (prepareView next (prepareView next state)).makeMarker = false := by
  rw [preparation_idempotent]
  exact changed_stamp_loses_marker next state changed

theorem native_success_corresponds (state : UnitState) :
    Corresponds (observeNativeSuccess state) := by simp [observeNativeSuccess, Corresponds]

/-- A crash after invalidation, or after writing the new descriptor but before
successful native compilation, leaves a missing marker. The Gerbil rebuilds that
unit. This is local ordering under serial operations, not filesystem atomicity. -/
theorem interrupted_preparation_rebuilds (next : Stamp) (state : UnitState)
    (changed : state.descriptor ≠ next) (roots : Nat) (sourcesStable dependenciesStable : Bool) :
    runtimeWork roots (prepareView next state).makeMarker sourcesStable dependenciesStable = roots := by
  rw [changed_stamp_loses_marker next state changed]
  exact missing_output_rebuilds roots sourcesStable dependenciesStable

theorem write_first_can_leave_stale_product (next : Stamp) (state : UnitState)
    (current : Corresponds state) (marker : state.makeMarker = true)
    (changed : state.descriptor ≠ next) : ¬ Corresponds (writeDescriptor next state) := by
  intro falseCurrent
  have oldProduct := current marker
  have newProduct := falseCurrent marker
  simp only [writeDescriptor] at newProduct
  rw [oldProduct] at newProduct
  exact changed (Option.some.inj newProduct)

/-- Preparation ordering is not a proof of interruption safety during native
compilation. A raw marker reappearing alongside old products cannot stand in
for observing successful compiler return and complete product admission. -/
theorem raw_marker_reappearance_is_insufficient (next : Stamp) (state : UnitState)
    (current : Corresponds state) (marker : state.makeMarker = true)
    (changed : state.descriptor ≠ next) :
    ¬ Corresponds { prepareView next state with makeMarker := true } := by
  intro falseCurrent
  have oldProduct := current marker
  have newProduct := falseCurrent rfl
  simp only [prepareView, invalidate, changed, ↓reduceIte, writeDescriptor] at newProduct
  rw [oldProduct] at newProduct
  exact changed (Option.some.inj newProduct)

/-- Native newer-than checks do not detect content/option changes with equal or
backdated mtimes. This theorem concerns that predicate, not filesystem accuracy. -/
def timestampRequestsBuild (inputTime outputTime : Nat) : Bool := decide (outputTime < inputTime)

theorem equal_timestamp_does_not_request_build (time : Nat) :
    timestampRequestsBuild time time = false := by simp [timestampRequestsBuild]

theorem backdated_input_does_not_request_build (inputTime outputTime : Nat)
    (backdated : inputTime ≤ outputTime) : timestampRequestsBuild inputTime outputTime = false := by
  simp [timestampRequestsBuild, Nat.not_lt.mpr backdated]

def oldStamp : Stamp := ⟨[("source.ss", some "old")], [], ["include-original"], "gerbil-toolchain", "native"⟩
def newStamp : Stamp := { oldStamp with observations := [("source.ss", some "new")] }
def oldState : UnitState := ⟨oldStamp, some oldStamp, true⟩

#guard (prepareView newStamp oldState).makeMarker == false
#guard (prepareView { oldStamp with options := ["-O2"] } oldState).makeMarker == false
#guard (prepareView { oldStamp with toolchain := "other-toolchain" } oldState).makeMarker == false
#guard (prepareView oldStamp oldState).makeMarker == true
example : ¬ Corresponds (writeDescriptor newStamp oldState) := by
  simp [Corresponds, writeDescriptor, newStamp, oldStamp, oldState]
example : Corresponds (prepareView newStamp oldState) := by
  exact invalidation_before_descriptor_is_safe newStamp oldState (by simp [Corresponds, oldState])

end YuanxuProof.ModuleSystem.Building.SourceView
