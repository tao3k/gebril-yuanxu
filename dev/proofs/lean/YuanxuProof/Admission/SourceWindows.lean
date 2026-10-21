-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.CacheLookup
import LeanPoo.Functional.ContextSlot
import YuanxuProof.Admission.Source

/-! Source bytes, POO values and admission certificates are different caches.
The filesystem is an actual read function, not a free revision oracle.
Stability inside a pure window and complete observation remain runtime premises. -/
namespace YuanxuProof.Admission.SourceWindows
def quintSourceDigest : String :=
  "sha256:c84947e04825b870b41caf9e060f2797d2e0a38cbc731db05463c319d048c53b"

open LeanPoo.Functional.ConstructionCache
abbrev World := String → Option String
abbrev Bytes := String → Option (Option String)

def Sound (cache : Bytes) (world : World) : Prop :=
  ∀ path value, cache path = some value → value = world path

def empty : Bytes := fun _ => none

def fetch (cache : Bytes) (world : World) (path : String) : Option String × Bytes :=
  let (result, next) := ensureLookup (Fault := Empty) cache path (fun _ => .ok (world path))
  match result with
  | .ok value => (value, next)
  | .error error => nomatch error

theorem empty_sound (world : World) : Sound empty world := by
  intro path value impossible
  simp [empty] at impossible

theorem fetch_value (cache : Bytes) (world : World) (path : String)
    (sound : Sound cache world) : (fetch cache world path).1 = world path := by
  cases found : cache path with
  | none => simp [fetch, ensureLookup, found]
  | some value => simpa [fetch, ensureLookup, found] using sound path value found

theorem fetch_sound (cache : Bytes) (world : World) (path : String)
    (sound : Sound cache world) : Sound (fetch cache world path).2 world := by
  cases found : cache path with
  | some value => simpa [fetch, ensureLookup, found] using sound
  | none =>
    simp only [fetch, ensureLookup, found]
    intro query value present
    by_cases same : query = path
    · subst query
      simpa using present.symm
    · simp [same] at present
      exact sound query value present

structure Checked where
  accepted : Bool
  cache : Bytes
  reads : Nat

def check (requirements : List (String × String)) (world : World) (cache : Bytes) : Checked :=
  match requirements with
  | [] => ⟨true, cache, 0⟩
  | (path, expected) :: rest =>
    let loaded := fetch cache world path
    let tail := check rest world loaded.2
    ⟨(loaded.1 == some expected) && tail.accepted, tail.cache,
      (if (cache path).isSome then 0 else 1) + tail.reads⟩

/-- Byte reuse never merges or discards competing requirements. -/
theorem check_exact (requirements : List (String × String)) (world : World) (cache : Bytes)
    (sound : Sound cache world) :
    (check requirements world cache).accepted = true ↔
      ∀ input ∈ requirements, world input.1 = some input.2 := by
  induction requirements generalizing cache with
  | nil => simp [check]
  | cons input rest ih =>
    rcases input with ⟨path, expected⟩
    simp only [check]
    rw [Bool.and_eq_true, beq_iff_eq, fetch_value cache world path sound,
      ih _ (fetch_sound cache world path sound)]
    simp

theorem fresh_exact (requirements : List (String × String)) (world : World) :
    (check requirements world empty).accepted = true ↔
      ∀ input ∈ requirements, world input.1 = some input.2 :=
  check_exact requirements world empty (empty_sound world)

theorem changed_source_rejected (requirements : List (String × String)) (world : World)
    (input : String × String) (member : input ∈ requirements)
    (changed : world input.1 ≠ some input.2) :
    (check requirements world empty).accepted = false := by
  cases accepted : (check requirements world empty).accepted with
  | false => rfl
  | true => exact False.elim (changed ((fresh_exact requirements world).mp accepted input member))

/-- Use the dependency's existing insertion/repeat law, not another cache engine. -/
theorem retained_read (cache : Bytes) (path : String) (value : Option String)
    (build again : Unit → Except Empty (Option String)) (missing : cache path = none)
    (built : build () = .ok value) :
    ensureLookup (ensureLookup cache path build).2 path again =
      (.ok value, (ensureLookup cache path build).2) :=
  ensureLookup_repeat cache path value build again missing built

#guard (check [("config.json", "old"), ("config.json", "old")] (fun _ => some "old") empty).reads == 1
#guard (check [("config.json", "old"), ("config.json", "new")] (fun _ => some "old") empty).accepted == false
#guard (check [("config.json", "old")] (fun _ => some "new") empty).accepted == false
#guard (check [("config.json", "old")] (fun _ => none) empty).accepted == false
-- The bad cross-effect optimization: its Sound premise is false.
#guard (check [("config.json", "old")] (fun _ => some "new")
  (fun _ => some (some "old"))).accepted == true

theorem read_bound (requirements : List (String × String)) (world : World) (cache : Bytes) :
    (check requirements world cache).reads ≤ requirements.length := by
  induction requirements generalizing cache with
  | nil => simp [check]
  | cons input rest ih =>
    rcases input with ⟨path, expected⟩
    have bound := ih (fetch cache world path).2
    change (if (cache path).isSome then 0 else 1) +
      (check rest world (fetch cache world path).2).reads ≤ rest.length + 1
    split <;> omega

theorem two_requirements_one_read (world : World) (path left right : String) :
    (check [(path, left), (path, right)] world empty).reads = 1 := by
  simp [check, fetch, ensureLookup, empty]

/-- Reuse Core's existing exact-text/absence source Obligation model. -/
theorem fresh_certificate (inputs : List (String × String)) (world : World) :
    (check inputs world empty).accepted = true ↔
      LeanPoo.Proof.Certificate (Source.sourceObject inputs world) := by
  rw [fresh_exact]
  simp [LeanPoo.Proof.Certificate, Source.sourceObject, Source.sourceObligation]

structure Receiver where

  identity : Nat
  revision : Nat
  port : Nat
  deriving DecidableEq

open LeanPoo.Functional.Requirements

theorem child_misses_parent {Value : Receiver → Nat → Type}
    {keys : List Nat} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (slot : ContextSlot ready)
    (parent child : Receiver) (data : Snapshot ready parent)
    (retained : slot.retained = some ⟨parent, data⟩) (different : parent ≠ child) :
    (slot.read child).2.2 = false := by
  simp [ContextSlot.read, retained, different]

theorem final_value {Value : Receiver → Nat → Type}
    {keys : List Nat} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (slot : ContextSlot ready) (child : Receiver) :
    (slot.read child).1.val = build ready.factories child :=
  ContextSlot.read_value slot child

end YuanxuProof.Admission.SourceWindows
