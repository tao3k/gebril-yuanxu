-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Object.Memo

/-! Partial open-method tables refine the locked LeanPoo CompiledPlan.
Opaque handles record observed identity, not extensional function equality.
Their correspondence to Scheme eq? remains a native implementation obligation.
No callbacks, value caches or admission conclusions are implemented here. -/
namespace YuanxuProof.ModuleSystem.Loading.DemandMaterialization
open LeanPoo
structure Scope where
  receiver : Nat
  revision : Nat
  deriving DecidableEq
variable {Key Value Handle : Type} [BEq Key] [LawfulBEq Key] [Hashable Key]
abbrev Methods (Key Value : Type) [BEq Key] [LawfulBEq Key] [Hashable Key] :=
  Object.CompiledPlan Key (fun _ => Value)
structure Cell (Key Value Handle : Type) where
  identity : Handle
  method : (Key → Option Value) → Option Value
structure Partial (Key Value Handle : Type) where
  scope : Scope
  cells : Key → Option (Cell Key Value Handle)
def empty (scope : Scope) : Partial Key Value Handle := ⟨scope, fun _ => none⟩
def Represents (full : Methods Key Value) (state : Partial Key Value Handle) : Prop :=
  ∀ key cell, state.cells key = some cell →
    key ∈ full.keys ∧ ∀ self, cell.method self = full.plan.resolve key self
/-- Hits ignore even a different offered handle. Missing keys are not installed. -/
def demand (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (offered : Handle) : Partial Key Value Handle :=
  if key ∈ full.keys then
    match state.cells key with
    | some _ => state
    | none => { state with cells := fun query =>
        if query == key then some ⟨offered, full.resolve key⟩ else state.cells query }
  else state

theorem empty_represents (full : Methods Key Value) (scope : Scope) :
    Represents full (empty scope : Partial Key Value Handle) := by
  intro key cell found
  simp [empty] at found

theorem demand_hit (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (cell : Cell Key Value Handle) (found : state.cells key = some cell)
    (offered : Handle) : demand full state key offered = state := by
  simp [demand, found]

theorem demand_unrelated (full : Methods Key Value) (state : Partial Key Value Handle)
    (key query : Key) (offered : Handle) (different : query ≠ key) :
    (demand full state key offered).cells query = state.cells query := by
  unfold demand
  split
  · split <;> simp_all
  · rfl

theorem demand_scope (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (offered : Handle) :
    (demand full state key offered).scope = state.scope := by
  unfold demand
  split
  · split <;> rfl
  · rfl

theorem demand_preserves_existing (full : Methods Key Value)
    (state : Partial Key Value Handle) (key query : Key) (offered : Handle)
    (cell : Cell Key Value Handle) (found : state.cells query = some cell) :
    (demand full state key offered).cells query = some cell := by
  unfold demand
  split
  · split
    · exact found
    · rename_i missing
      by_cases same : query = key
      · subst query
        simp_all
      · simpa [same] using found
  · exact found

theorem demand_present (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (offered : Handle) (declared : key ∈ full.keys) :
    ∃ cell, (demand full state key offered).cells key = some cell := by
  unfold demand
  simp only [declared, ↓reduceIte]
  split
  · rename_i cell found
    exact ⟨cell, found⟩
  · exact ⟨⟨offered, full.resolve key⟩, by simp⟩

theorem first_install_identity (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (offered : Handle) (declared : key ∈ full.keys)
    (missing : state.cells key = none) :
    ((demand full state key offered).cells key).map Cell.identity = some offered := by
  simp [demand, declared, missing]

theorem repeated_demand_stable (full : Methods Key Value) (state : Partial Key Value Handle)
    (key : Key) (first second : Handle) (declared : key ∈ full.keys) :
    demand full (demand full state key first) key second = demand full state key first := by
  obtain ⟨cell, found⟩ := demand_present full state key first declared
  exact demand_hit full _ key cell found second

theorem demand_represents (full : Methods Key Value)
    (state : Partial Key Value Handle) (sound : Represents full state)
    (key : Key) (offered : Handle) : Represents full (demand full state key offered) := by
  intro query cell found
  unfold demand at found
  split at found
  · rename_i declared
    split at found
    · exact sound query cell found
    · by_cases same : query = key
      · subst query
        simp only [BEq.rfl, ↓reduceIte, Option.some.injEq] at found
        subst cell
        exact ⟨declared, fun self => full.resolve_sound key declared self⟩
      · simp only [show (query == key) = false from beq_eq_false_iff_ne.mpr same,
          Bool.false_eq_true, ↓reduceIte] at found
        exact sound query cell found
  · exact sound query cell found

def complete (full : Methods Key Value) (state : Partial Key Value Handle)
    (offered : Key → Handle) : Partial Key Value Handle :=
  full.keys.foldl (fun state key => demand full state key (offered key)) state

theorem fold_preserves_existing (full : Methods Key Value) (keys : List Key)
    (state : Partial Key Value Handle) (offered : Key → Handle) (query : Key)
    (cell : Cell Key Value Handle) (found : state.cells query = some cell) :
    (keys.foldl (fun state key => demand full state key (offered key)) state).cells query = some cell := by
  induction keys generalizing state with
  | nil => exact found
  | cons key rest ih =>
    exact ih _ (demand_preserves_existing full state key query (offered key) cell found)

theorem fold_represents (full : Methods Key Value) (keys : List Key)
    (state : Partial Key Value Handle) (offered : Key → Handle)
    (sound : Represents full state) :
    Represents full (keys.foldl (fun state key => demand full state key (offered key)) state) := by
  induction keys generalizing state with
  | nil => exact sound
  | cons key rest ih => exact ih _ (demand_represents full state sound key (offered key))

theorem fold_covers (full : Methods Key Value) (keys : List Key)
    (state : Partial Key Value Handle) (offered : Key → Handle) (query : Key)
    (member : query ∈ keys) (declared : query ∈ full.keys) :
    ∃ cell, (keys.foldl (fun state key => demand full state key (offered key)) state).cells query = some cell := by
  induction keys generalizing state with
  | nil => simp at member
  | cons key rest ih =>
    rcases List.mem_cons.mp member with same | later
    · subst query
      obtain ⟨cell, found⟩ := demand_present full state key (offered key) declared
      exact ⟨cell, fold_preserves_existing full rest _ offered key cell found⟩
    · exact ih _ later

theorem complete_represents (full : Methods Key Value)
    (state : Partial Key Value Handle) (offered : Key → Handle)
    (sound : Represents full state) : Represents full (complete full state offered) :=
  fold_represents full full.keys state offered sound

theorem complete_lookup (full : Methods Key Value)
    (state : Partial Key Value Handle) (offered : Key → Handle)
    (sound : Represents full state) (key : Key) (declared : key ∈ full.keys) :
    ∃ cell, (complete full state offered).cells key = some cell ∧
      ∀ self, cell.method self = full.plan.resolve key self := by
  obtain ⟨cell, found⟩ := fold_covers full full.keys state offered key declared declared
  exact ⟨cell, found, (complete_represents full state offered sound key cell found).2⟩

theorem reflection_identity (full : Methods Key Value)
    (state : Partial Key Value Handle) (offered : Key → Handle)
    (key : Key) (cell : Cell Key Value Handle) (found : state.cells key = some cell) :
    (complete full state offered).cells key = some cell :=
  fold_preserves_existing full full.keys state offered key cell found

/-- Absence in a state table is pending metadata, not absence from full.keys. -/
def lookupAt (scope : Scope) (state : Partial Key Value Handle) (key : Key) :
    Option (Cell Key Value Handle) :=
  if state.scope = scope then state.cells key else none

omit [BEq Key] [LawfulBEq Key] [Hashable Key] in
theorem different_scope_rejected (state : Partial Key Value Handle) (scope : Scope)
    (different : state.scope ≠ scope) (key : Key) : lookupAt scope state key = none := by
  simp [lookupAt, different]

def reset (_ : Partial Key Value Handle) (scope : Scope) : Partial Key Value Handle := empty scope

omit [BEq Key] [LawfulBEq Key] [Hashable Key] in
theorem reset_has_no_parent_cell (state : Partial Key Value Handle) (scope : Scope) (key : Key) :
    (reset state scope).cells key = none := rfl
end YuanxuProof.ModuleSystem.Loading.DemandMaterialization
