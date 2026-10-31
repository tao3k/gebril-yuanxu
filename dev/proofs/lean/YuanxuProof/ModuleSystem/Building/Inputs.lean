-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation
import YuanxuProof.Admission.Source

namespace YuanxuProof.ModuleSystem.Building.Inputs
open LeanPoo.Functional
open LeanPoo.Proof
open YuanxuProof.Admission.Source

/-! `source/build.ss:unique-build-inputs` and `add!`, and
`building/build-projection.ss:merge-build-entries`. None normalizes contradictory
snapshots away. Native reference/normalized path identities are explicit inputs. -/
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

/-- A canonical SDK context is projected by reference AND source path. Shared
artifact definitions may live beside a Module; its publication roles are still
forbidden as implicit compiler inputs. Native context discovery is observed. -/
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
