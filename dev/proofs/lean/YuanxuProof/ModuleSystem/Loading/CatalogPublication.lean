-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

namespace YuanxuProof.ModuleSystem.Loading.CatalogPublication

-- Names and exact versions project to keys. Release stamps stand for the
-- identity of immutable native release records, not an equality on contents.
abbrev Key := Nat × Nat
abbrev Snapshot := Key → Option Nat

def singletonVersion (version stamp : Nat) (query : Nat) : Option Nat :=
  if query = version then some stamp else none

/-- The single-release representation projects exactly the same point reads
as promotion to the version index. A duplicate version is rejected before
either representation can replace the issued stamp. -/
theorem promote_singleton_version (first firstStamp second secondStamp : Nat)
    (distinct : second ≠ first) (query : Nat) :
    (if query = second then some secondStamp else singletonVersion first firstStamp query) =
      (if query = first then some firstStamp else singletonVersion second secondStamp query) := by
  by_cases hit : query = second
  · simp [hit, distinct, singletonVersion]
  · simp [hit, singletonVersion]

/-- Gerbil's interned symbol is the canonical representative of its spelling.
Skipping its spelling round trip preserves the lookup key. Symbols outside
that domain still go through the interning operation. -/
theorem canonical_symbol_fast_path {Symbol Spelling : Type}
    (interned : Symbol → Bool) (spelling : Symbol → Spelling) (intern : Spelling → Symbol)
    (fixed : ∀ symbol, interned symbol = true → intern (spelling symbol) = symbol)
    (symbol : Symbol) :
    (if interned symbol then symbol else intern (spelling symbol)) = intern (spelling symbol) := by
  cases known : interned symbol
  · rfl
  · simpa using (fixed symbol known).symm

/-- The current version bucket can serve consecutive rows of its own name.
Interleaved names still read the complete outer index. -/
theorem current_bucket_lookup_exact {Name Bucket : Type} [DecidableEq Name]
    (outer : Name → Bucket) (owner : Name) (bucket : Bucket)
    (current : outer owner = bucket) (query : Name) :
    (if query = owner then bucket else outer query) = outer query := by
  by_cases hit : query = owner
  · simp [hit, current]
  · simp [hit]

structure Edit where
  key : Key
  expected : Option Nat
  replacement : Option Nat

def applyEdit (base : Snapshot) (edit : Edit) : Option Snapshot :=
  if base edit.key = edit.expected then
    some (fun key => if key = edit.key then edit.replacement else base key)
  else none

def publish (base : Snapshot) (edits : List Edit) : Option Snapshot :=
  match edits with
  | [] => some base
  | edit :: rest => (applyEdit base edit).bind fun next => publish next rest

theorem exact_edit (base : Snapshot) (edit : Edit)
    (current : base edit.key = edit.expected) :
    (applyEdit base edit).map (fun next => next edit.key) = some edit.replacement := by
  simp [applyEdit, current]

theorem rejects_conflict (base : Snapshot) (edit : Edit) (tail : List Edit)
    (stale : base edit.key ≠ edit.expected) :
    publish base (edit :: tail) = none := by
  simp [publish, applyEdit, stale]

theorem publish_append (base : Snapshot) (earlier later : List Edit) :
    publish base (earlier ++ later) =
      (publish base earlier).bind fun interim => publish interim later := by
  induction earlier generalizing base with
  | nil => rfl
  | cons edit rest ih =>
    cases step : applyEdit base edit with
    | none => simp [publish, step]
    | some next => simpa [publish, step] using ih next

theorem conflict_discards_provisional_result (base interim : Snapshot)
    (earlier : List Edit) (edit : Edit) (tail : List Edit)
    (provisional : publish base earlier = some interim)
    (stale : interim edit.key ≠ edit.expected) :
    publish base (earlier ++ edit :: tail) = none := by
  rw [publish_append, provisional]
  exact rejects_conflict interim edit tail stale

theorem preserves_untouched (base next : Snapshot) (edits : List Edit) (key : Key)
    (outside : ∀ edit ∈ edits, key ≠ edit.key)
    (accepted : publish base edits = some next) : next key = base key := by
  induction edits generalizing base with
  | nil =>
    simp [publish] at accepted
    rw [accepted]
  | cons edit rest ih =>
    by_cases current : base edit.key = edit.expected
    · let updated : Snapshot := fun query =>
        if query = edit.key then edit.replacement else base query
      have tail : publish updated rest = some next := by
        simpa [publish, applyEdit, current, updated] using accepted
      have same := ih updated (fun other member => outside other (List.mem_cons_of_mem edit member)) tail
      simpa [updated, outside edit (by simp)] using same
    · simp [publish, applyEdit, current] at accepted

/-- The requested versions of any untouched name give the same release
projection, in the caller's order and with the same omissions. -/
theorem preserves_other_name_projection (base next : Snapshot) (edits : List Edit)
    (name : Nat) (versions : List Nat)
    (outside : ∀ edit ∈ edits, name ≠ edit.key.1)
    (accepted : publish base edits = some next) :
    versions.filterMap (fun version => next (name, version)) =
      versions.filterMap (fun version => base (name, version)) := by
  apply congrArg (fun lookup => versions.filterMap lookup)
  funext version
  apply preserves_untouched base next edits (name, version) _ accepted
  intro edit member equal
  exact outside edit member (congrArg Prod.fst equal)

def dependencyDemand {α : Type} (snapshot : Snapshot) (key : Key) (release : Nat)
    (read : Nat → α) : Option α :=
  if snapshot key = some release then some (read release) else none

theorem stale_release_has_no_dependency_result {α : Type} (snapshot : Snapshot)
    (key : Key) (release : Nat) (read : Nat → α) (stale : snapshot key ≠ some release) :
    dependencyDemand snapshot key release read = none := by
  simp [dependencyDemand, stale]

end YuanxuProof.ModuleSystem.Loading.CatalogPublication
