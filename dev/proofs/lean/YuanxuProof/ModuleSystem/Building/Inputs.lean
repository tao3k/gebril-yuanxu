-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation
import YuanxuProof.Admission.Source

namespace YuanxuProof.ModuleSystem.Building.Inputs
open LeanPoo.Functional
open LeanPoo.Proof
open YuanxuProof.Admission.Source

/-! `source/build.ss:unique-build-inputs` and `add!`, and
`building/build-projection.ss:merge-build-entries`. None normalizes contradictory
snapshots away. Runtime reference/normalized path identities are explicit inputs. -/
def insertObservation (seen : List (String × Option String)) (input : String × Option String) :
    Except String (List (String × Option String)) :=
  match seen.find? (fun previous => previous.1 == input.1) with
  | none => .ok (seen ++ [input])
  | some previous => if previous.2 = input.2 then .ok seen else .error input.1

def uniqueInputs : List (String × Option String) → List (String × Option String) →
    Except String (List (String × Option String))
  | seen, [] => .ok seen
  | seen, input :: rest => (insertObservation seen input).bind (fun next => uniqueInputs next rest)

/-- Re-observe the complete input set before consuming its deduplicated value.
Absence remains an observation: a newly created previously absent file is stale.
The dependency factory retains the exact source-read context for both checks. -/
def checkedInputs (inputs : List (String × Option String)) :
    Factory (String → Option String) (fun _ => Except String (List (String × Option String))) :=
  Factory.choose (fun read => inputs.all (fun input => read input.1 == input.2))
    (fun _ => uniqueInputs [] inputs) (fun _ => .error "changed build input")

theorem changed_input_rejected (inputs : List (String × Option String))
    (read : String → Option String)
    (stale : inputs.all (fun input => read input.1 == input.2) = false) :
    checkedInputs inputs read = .error "changed build input" := by
  simp [checkedInputs, Factory.choose, stale]

/-- A canonical Gerbil expander context is projected by reference AND source path. Shared
artifact definitions may live beside a Module; its publication roles are still
forbidden as implicit compiler inputs. Runtime context discovery is observed. -/
structure ToolSource where
  reference : Nat
  path : String
  deriving Repr, DecidableEq

def admitToolSource (registered : List ToolSource) (roles : List String)
    (candidate : ToolSource) : Except String ToolSource :=
  if candidate ∈ registered ∧ candidate.path ∉ roles then .ok candidate
  else .error "not a shared compiler definition"

theorem tool_source_accepted_iff (registered : List ToolSource) (roles : List String)
    (candidate : ToolSource) :
    admitToolSource registered roles candidate = .ok candidate ↔
      candidate ∈ registered ∧ candidate.path ∉ roles := by
  by_cases valid : candidate ∈ registered ∧ candidate.path ∉ roles <;>
    simp [admitToolSource, valid]

theorem publication_role_not_a_tool (registered : List ToolSource) (roles : List String)
    (candidate : ToolSource) (role : candidate.path ∈ roles) :
    admitToolSource registered roles candidate = .error "not a shared compiler definition" := by
  simp [admitToolSource, role]

def checkedToolSource (inputs : List (String × Option String))
    (registered : List ToolSource) (roles : List String) (candidate : ToolSource) :
    Factory (String → Option String) (fun _ => Except String ToolSource) :=
  Factory.map (fun _ checked => checked.bind (fun _ => admitToolSource registered roles candidate))
    (checkedInputs inputs)

theorem changed_tool_source_rejected (inputs : List (String × Option String))
    (registered : List ToolSource) (roles : List String) (candidate : ToolSource)
    (read : String → Option String)
    (stale : inputs.all (fun input => read input.1 == input.2) = false) :
    checkedToolSource inputs registered roles candidate read = .error "changed build input" := by
  simp [checkedToolSource, Factory.map, changed_input_rejected inputs read stale, Except.bind]

/-- Adding an actual kernel library context changes eligibility, not source
certification. A different same-path instance is not made eligible by name. -/
theorem registered_extension_preserves_tool (registered extra : List ToolSource)
    (roles : List String) (candidate : ToolSource)
    (accepted : admitToolSource registered roles candidate = .ok candidate) :
    admitToolSource (registered ++ extra) roles candidate = .ok candidate := by
  apply (tool_source_accepted_iff _ _ _).mpr
  obtain ⟨member, ordinary⟩ := (tool_source_accepted_iff _ _ _).mp accepted
  exact ⟨List.mem_append_left extra member, ordinary⟩

theorem catalog_extension_keeps_source_refusal (inputs : List (String × Option String))
    (registered extra : List ToolSource) (roles : List String) (candidate : ToolSource)
    (read : String → Option String)
    (stale : inputs.all (fun input => read input.1 == input.2) = false) :
    checkedToolSource inputs (registered ++ extra) roles candidate read =
      .error "changed build input" :=
  changed_tool_source_rejected inputs (registered ++ extra) roles candidate read stale

theorem catalog_extension_keeps_role_refusal (registered extra : List ToolSource)
    (roles : List String) (candidate : ToolSource) (role : candidate.path ∈ roles) :
    admitToolSource (registered ++ extra) roles candidate =
      .error "not a shared compiler definition" :=
  publication_role_not_a_tool (registered ++ extra) roles candidate role

#guard (admitToolSource [⟨1, "schema/values.ss"⟩] ["schema/interface.ss"]
  ⟨1, "schema/values.ss"⟩).toOption.isSome
#guard !(admitToolSource [⟨1, "schema/values.ss"⟩] [] ⟨2, "schema/values.ss"⟩).toOption.isSome
#guard !(admitToolSource [⟨1, "schema/interface.ss"⟩] ["schema/interface.ss"]
  ⟨1, "schema/interface.ss"⟩).toOption.isSome

theorem duplicate_agrees (path : String) (text : Option String) :
    insertObservation [(path, text)] (path, text) = .ok [(path, text)] := by
  simp [insertObservation]

theorem contradictory_snapshot_rejected (path : String) (before after : Option String) (changed : before ≠ after) :
    insertObservation [(path, before)] (path, after) = .error path := by simp [insertObservation, changed]

-- A narrowed runtime import keeps the original source/phase edge. Only its
-- strong alias inventory changes. Actual macro-use coverage is a compiler
-- correspondence obligation, not inferred from textual token counting.
structure ImportView where
  source : Nat
  phase : Int
  bindings : List (String × Nat)
  deriving Repr, DecidableEq

def narrowImport (view : ImportView) (names : List String) : ImportView :=
  { view with bindings := view.bindings.filter (fun row => decide (row.1 ∈ names)) }

def firstBinding (name : String) : List (String × Nat) → Option Nat
  | [] => none
  | row :: rest => if row.1 = name then some row.2 else firstBinding name rest

theorem narrowed_import_edge (view : ImportView) (names : List String) :
    (narrowImport view names).source = view.source ∧
    (narrowImport view names).phase = view.phase := ⟨rfl, rfl⟩

theorem narrowed_binding_identity (view : ImportView) (names : List String)
    (name : String) (used : name ∈ names) :
    firstBinding name (narrowImport view names).bindings = firstBinding name view.bindings := by
  rcases view with ⟨source, phase, bindings⟩
  simp only [narrowImport]
  induction bindings with
  | nil => rfl
  | cons row rest ih =>
    by_cases same : row.1 = name
    · have kept : row.1 ∈ names := by simpa [same] using used
      simp [List.filter, firstBinding, same, used]
    · by_cases kept : row.1 ∈ names <;> simp [List.filter, firstBinding, kept, same, ih]

def bindingWithPrelude (direct inherited : Option Nat) : Option Nat :=
  match direct with
  | some identity => some identity
  | none => inherited

/-- Gerbil's public export name and defining lexical key are distinct. This
projects existing binding metadata; it does not rewrite the defining Context. -/
def exportedBinding (bindings : List (String × Nat)) (publicName localKey : String) :
    Option (String × Nat) :=
  (firstBinding localKey bindings).map (fun reference => (publicName, reference))

theorem renamed_export_keeps_reference (bindings : List (String × Nat))
    (publicName localKey : String) (reference : Nat)
    (bound : firstBinding localKey bindings = some reference) :
    exportedBinding bindings publicName localKey = some (publicName, reference) := by
  simp [exportedBinding, bound]

/-- The concrete Prelude regression: retaining POO's internal .def and
publishing role-.def as .def makes internal-name lookup the WRONG oracle. -/
theorem role_export_is_not_internal_lookup (poo role : Nat) (different : poo ≠ role) :
    exportedBinding [(".def", poo), ("role-.def", role)] ".def" "role-.def" ≠
      (firstBinding ".def" [(".def", poo), ("role-.def", role)]).map
        (fun reference => (".def", reference)) := by
  simp [exportedBinding, firstBinding, Ne.symm different]

/-- A binding-preserving substitution must also preserve the observable
initializer identity and its authority. A shared source path is only one
component. These are observations, not an authorization certificate. -/
structure ContextUse where
  source : String
  phase : Int
  definingBinding : Nat
  initializer : Nat
  owner : Nat
  deriving DecidableEq

def reuseContext (expected actual : ContextUse) (check : Unit → Except String Unit) :
    Except String Bool :=
  if expected = actual then (check ()).map (fun _ => true) else .ok false

theorem same_source_distinct_binding_separates (expected actual : ContextUse)
    (different : expected.definingBinding ≠ actual.definingBinding)
    (check : Unit → Except String Unit) :
    reuseContext expected actual check = .ok false := by
  have distinct : expected ≠ actual :=
    fun eq => different (congrArg ContextUse.definingBinding eq)
  simp [reuseContext, distinct]

theorem context_reuse_keeps_rejection (use : ContextUse) (check : Unit → Except String Unit)
    (message : String) (stale : check () = .error message) :
    reuseContext use use check = .error message := by
  simp [reuseContext, stale, Except.map]

/-- Source projection uses the admitted native prerequisites first. Runtime
execution uses the selected products first. Make's output inventory is a
separate argument; changing lookup order never changes the selected targets. -/
def compilerLookup (prerequisite product : Option ContextUse) : Option ContextUse :=
  prerequisite.orElse fun _ => product

def consumerLookup (prerequisite product : Option ContextUse) : Option ContextUse :=
  product.orElse fun _ => prerequisite

theorem compiler_context_stable_across_build (input : ContextUse)
    (cold hot : Option ContextUse) :
    compilerLookup (some input) cold = compilerLookup (some input) hot := by rfl

theorem consumer_uses_selected_product (input : Option ContextUse) (product : ContextUse) :
    consumerLookup input (some product) = some product := by rfl

theorem absent_prerequisite_keeps_native_fallback (product : Option ContextUse) :
    compilerLookup none product = product := by rfl

theorem compiler_lookup_keeps_currentness_failure (input : ContextUse)
    (product : Option ContextUse) (check : Unit → Except String Unit)
    (message : String) (stale : check () = .error message) :
    reuseContext input ((compilerLookup (some input) product).getD input) check = .error message := by
  exact context_reuse_keeps_rejection input check message stale

/-- Existing products remain available as fallback; only their position moves.
The relative prerequisite order is preserved by the first filter. -/
def compilerPath (output : Nat) (paths : List Nat) : List Nat :=
  paths.filter (fun path => path != output) ++ paths.filter (fun path => path == output)

theorem compiler_path_membership (output path : Nat) (paths : List Nat) :
    path ∈ compilerPath output paths ↔ path ∈ paths := by
  by_cases same : path = output <;> simp [compilerPath, same]

def reuseBuildSpec (refused : Bool) (prepared : Option α) : Except String (Option α) :=
  if refused then .error "input context refused" else .ok prepared

theorem refused_epoch_never_reuses_prepared (prepared : Option α) :
    reuseBuildSpec true prepared = .error "input context refused" := by rfl

#guard compilerPath 9 [9, 1, 2, 9] == [1, 2, 9, 9]

/-- An explicit Make output may be absent from the runtime path. It still
belongs at the end of the compiler path. -/
def compilerPathWithFallback (output : Nat) (paths : List Nat) : List Nat :=
  compilerPath output paths ++ (if output ∈ paths then [] else [output])

theorem compiler_path_contains_output (output : Nat) (paths : List Nat) :
    output ∈ compilerPathWithFallback output paths := by
  by_cases present : output ∈ paths <;>
    simp [compilerPathWithFallback, present, compiler_path_membership]

#guard compilerPathWithFallback 9 [1, 2] == [1, 2, 9]
#guard compilerPathWithFallback 9 [9, 1, 2] == [1, 2, 9]

/-- A declared native checkout takes priority over an installed copy and
the consumer output. The candidate is eligible only after native identity
and owner admission, which are checked by the source reader. -/
def compilerLookupWithSource (prerequisite source product : Option ContextUse) :
    Option ContextUse :=
  source.orElse fun _ => prerequisite.orElse fun _ => product

theorem declared_compiler_source_precedes_installed_copy (source : ContextUse)
    (prerequisite product : Option ContextUse) :
    compilerLookupWithSource prerequisite (some source) product = some source := rfl

theorem missing_compiler_source_preserves_prerequisite (input : ContextUse)
    (product : Option ContextUse) :
    compilerLookupWithSource (some input) none product = some input := rfl

theorem compiler_source_is_stable_across_output (source : ContextUse)
    (prerequisite cold hot : Option ContextUse) :
    compilerLookupWithSource prerequisite (some source) cold =
      compilerLookupWithSource prerequisite (some source) hot := rfl

theorem missing_compiler_source_preserves_output (product : Option ContextUse) :
    compilerLookupWithSource none none product = product := rfl

/-- Gerbil's single-directory resolver skips a registered package directory
when its prefix differs. Bound preludes and the package's language entry are
resolved before reaching that directory search. -/
def ownedLookup (bound language candidate : Option String) (prefixMatches : Bool) :
    Option String :=
  bound.orElse fun _ => language.orElse fun _ => if prefixMatches then candidate else none

theorem foreign_directory_has_no_candidate (candidate : Option String) :
    ownedLookup none none candidate false = none := rfl

theorem bound_language_precedes_directory (path : String) (candidate : Option String) :
    ownedLookup none (some path) candidate false = some path := rfl

-- A runtime dependency marker carries no aliases. This replacement is valid
-- only when runtime resolution proves that the existing prelude supplies the
-- SAME binding, not merely a matching name or a user-provided capability tag.
theorem runtime_prelude_binding_identity (identity : Nat) :
    bindingWithPrelude none (some identity) =
      bindingWithPrelude (some identity) (some identity) := rfl

-- Internal value factories import one fresh public name into a runtime top
-- context. The shared language frame changes storage, not name/phase lookup.
-- The Scheme correspondence checks actual exported binding identities; this
-- statement does not certify arbitrary strong-name collision behavior.
def factoryLookup (language : String → Int → Option Nat)
    (name : String) (phase : Int) (binding : Nat)
    (query : String) (queryPhase : Int) : Option Nat :=
  if query = name ∧ queryPhase = phase then some binding else language query queryPhase

theorem factory_language_storage_independent
    (direct inherited : String → Int → Option Nat)
    (same : ∀ name phase, direct name phase = inherited name phase)
    (name query : String) (phase queryPhase : Int) (binding : Nat) :
    factoryLookup direct name phase binding query queryPhase =
      factoryLookup inherited name phase binding query queryPhase := by
  unfold factoryLookup
  split
  · rfl
  · exact same query queryPhase

theorem factory_target_identity (language : String → Int → Option Nat)
    (name : String) (phase : Int) (binding : Nat) :
    factoryLookup language name phase binding name phase = some binding := by
  simp [factoryLookup]

-- The prelude alone is insufficient: another surviving strong import may
-- shadow it (notably gerbil/core's object? and make-object). Removal must prove
-- the COMPLETE remaining lookup, rather than compare just the prelude.
theorem remaining_bindings_preserve_identity (identity : Nat)
    (remaining inherited : Option Nat)
    (same : bindingWithPrelude remaining inherited = some identity) :
    bindingWithPrelude (some identity) (bindingWithPrelude remaining inherited) =
      bindingWithPrelude remaining inherited := by
  change some identity = bindingWithPrelude remaining inherited
  exact same.symm

theorem remaining_shadow_blocks_removal (wanted shadow : Nat) (different : shadow ≠ wanted) :
    bindingWithPrelude (some shadow) (some wanted) ≠ some wanted := by
  simpa [bindingWithPrelude] using different

def runtimeImport (view : ImportView) : ImportView := { view with bindings := [] }

theorem runtime_import_edge (view : ImportView) :
    (runtimeImport view).source = view.source ∧
      (runtimeImport view).phase = view.phase := ⟨rfl, rfl⟩

/-- A runtime lexical slot captures an immutable value. This does not apply to
receiver formulas, defaults, callbacks or mutable captured variables. -/
def lexicalValue {α : Type} (value : α) : Factory Nat (fun _ => α) := fun _ => value

theorem lexical_value_receiver_independent {α : Type} (value : α) (parent child : Nat) :
    lexicalValue value parent = lexicalValue value child := rfl

theorem lexical_value_identity {α : Type} (value : α) (receiver : Nat) :
    lexicalValue value receiver = value := rfl

/-- This only normalizes repeated aliases whose actual runtime owner is the
same context. Export-binding/phase/weakness equivalence is a runtime audit
obligation; arbitrary reexports or effectful timestamp queries are not equated. -/
theorem grouped_runtime_owner_reachability (owner candidate : Nat) (aliases : Nat) :
    candidate ∈ List.replicate (aliases + 1) owner ↔ candidate ∈ [owner] := by
  simp

-- Count only explicit frame-pair/spine cons cells at the source call sites,
-- on the SAME candidate/descend trace. This is not VM or retained byte cost.
def copiedFrameCells (candidates descents : Nat) := 2 + 2 * candidates + 2 * descents
def cursorFrameCells (descents : Nat) := 2 * descents

theorem cursor_frame_cells_saved (candidates descents : Nat) :
    copiedFrameCells candidates descents =
      cursorFrameCells descents + 2 * (candidates + 1) := by
  simp only [copiedFrameCells, cursorFrameCells]
  omega

structure Entry where
  path : String
  compilerIdentity : String
  kind : String
  options : List String
  compilerForms : List String
  deriving Repr, DecidableEq

inductive Failure where
  | pathConflict | duplicateIdentity | compilerConflict
  deriving Repr, DecidableEq

/-- Selected Graph `add!`: an already seen path compares kind/options before
checking compiler IDs; a different path cannot reuse an existing compiler ID. -/
def add (seen : List Entry) (candidate : Entry) : Except Failure (List Entry) :=
  match seen.find? (fun previous => previous.path == candidate.path) with
  | some previous =>
    if previous.kind = candidate.kind ∧ previous.options = candidate.options then .ok seen
    else .error .pathConflict
  | none =>
    if seen.any (fun previous => previous.compilerIdentity == candidate.compilerIdentity) then .error .duplicateIdentity
    else .ok (seen ++ [candidate])

/-- Retained target merge uses all THREE equality checks, including forms. -/
def mergeEntry (seen : List Entry) (candidate : Entry) : Except Failure (List Entry) :=
  match seen.find? (fun previous => previous.compilerIdentity == candidate.compilerIdentity) with
  | none => .ok (seen ++ [candidate])
  | some previous =>
    if previous.path = candidate.path ∧ previous.options = candidate.options ∧ previous.compilerForms = candidate.compilerForms
    then .ok seen else .error .compilerConflict

theorem different_forms_rejected (previous candidate : Entry)
    (identity : previous.compilerIdentity = candidate.compilerIdentity)
    (changed : previous.compilerForms ≠ candidate.compilerForms) :
    mergeEntry [previous] candidate = .error .compilerConflict := by
  simp [mergeEntry, identity, changed]

theorem duplicate_identity_rejected (previous candidate : Entry)
    (identity : previous.compilerIdentity = candidate.compilerIdentity) (differentPath : previous.path ≠ candidate.path) :
    add [previous] candidate = .error .duplicateIdentity := by simp [add, identity, differentPath]

/-- Both compiler and reader lower Build to the same capability check. Lookup
is lazy and even a retained value is gated on EVERY use, outside the cache. -/
def demandBuild (buildPhase : Bool) (retained : Option Value) : Except Unit (Option Value) :=
  if buildPhase then .ok retained else .error ()

theorem cached_build_cannot_escape_phase (retained : Option Value) :
    demandBuild false retained = .error () := rfl

#guard (uniqueInputs [] [("a.ss", some "one"), ("a.ss", some "two")]).toOption == none
#guard (uniqueInputs [] [("missing.ss", none), ("missing.ss", none)]).toOption == some [("missing.ss", none)]
#guard (checkedInputs [("missing.ss", none)] (fun _ => some "created")).toOption == none
#guard (demandBuild false (some 7)).toOption == none
end YuanxuProof.ModuleSystem.Building.Inputs
