-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.RootChild

/-! Pure source-check composition AFTER an effect boundary. Reuse is derived
from the actual read function and LeanPoo ensureLookup, never from an epoch tag.
This does not classify an arbitrary Scheme callback or MOP token as pure. -/
namespace YuanxuProof.Admission.ReturnWindows
open SourceWindows LeanPoo.Functional.ConstructionCache

-- Refreshed from the maintained QNT source before qualification.
def quintSourceDigest : String :=
  "sha256:4f096b2dc8d9604ca5a6b8d47dc097a2a02d2138e5d7c9150ccca2ffc8e86c3a"

def combine (first second : Checked) : Checked :=
  ⟨first.accepted && second.accepted, second.cache, first.reads + second.reads⟩

/-- Sequential pure checking is exactly concatenation, including cache and cost.
The list retains conflicting requirements and duplicate contributors. -/
theorem check_append (left right : List (String × String)) (world : World) (cache : Bytes) :
    check (left ++ right) world cache =
      combine (check left world cache) (check right world (check left world cache).cache) := by
  induction left generalizing cache with
  | nil => simp [check, combine]
  | cons input rest ih =>
    rcases input with ⟨path, expected⟩
    simp [check, ih, combine, Bool.and_assoc, Nat.add_assoc]

theorem check_sound (requirements : List (String × String)) (world : World) (cache : Bytes)
    (sound : Sound cache world) : Sound (check requirements world cache).cache world := by
  induction requirements generalizing cache with
  | nil => simpa [check] using sound
  | cons input rest ih =>
    exact ih _ (fetch_sound cache world input.1 sound)

private theorem fetch_retains (cache : Bytes) (world : World) (path query : String)
    (value : Option String) (present : cache query = some value) :
    (fetch cache world path).2 query = some value := by
  cases found : cache path with
  | some old => simpa [fetch, ensureLookup, found] using present
  | none =>
    by_cases same : query = path
    · subst query; simp_all
    · simpa [fetch, ensureLookup, found, same] using present

private theorem fetch_present (cache : Bytes) (world : World) (path : String) :
    ∃ value, (fetch cache world path).2 path = some value := by
  cases found : cache path with
  | some value => exact ⟨value, by simp [fetch, ensureLookup, found]⟩
  | none => exact ⟨world path, by simp [fetch, ensureLookup, found]⟩

theorem check_retains (requirements : List (String × String)) (world : World) (cache : Bytes)
    (path : String) (value : Option String) (present : cache path = some value) :
    (check requirements world cache).cache path = some value := by
  induction requirements generalizing cache with
  | nil => simpa [check] using present
  | cons input rest ih => exact ih _ (fetch_retains cache world input.1 path value present)

theorem checked_path_present (requirements : List (String × String)) (world : World)
    (cache : Bytes) (input : String × String) (member : input ∈ requirements) :
    ∃ value, (check requirements world cache).cache input.1 = some value := by
  induction requirements generalizing cache with
  | nil => simp at member
  | cons head rest ih =>
    rcases List.mem_cons.mp member with same | later
    · subst head
      obtain ⟨value, present⟩ := fetch_present cache world input.1
      exact ⟨value, check_retains rest world _ input.1 value present⟩
    · exact ih _ later

theorem cached_reads_zero (requirements : List (String × String)) (world : World)
    (cache : Bytes)
    (covered : ∀ input ∈ requirements, ∃ value, cache input.1 = some value) :
    (check requirements world cache).reads = 0 := by
  induction requirements generalizing cache with
  | nil => rfl
  | cons input rest ih =>
    obtain ⟨value, present⟩ := covered input (by simp)
    have tail := ih cache (fun entry member => covered entry (List.mem_cons_of_mem _ member))
    simpa [check, fetch, ensureLookup, present] using tail

/-- In one stable world a repeated/subset check needs no additional file read.
It STILL compares every expectation; path coverage alone cannot grant admission. -/
theorem covered_suffix_zero_reads (first suffix : List (String × String)) (world : World)
    (cache : Bytes) (coverage : ∀ input ∈ suffix, input ∈ first) :
    (check suffix world (check first world cache).cache).reads = 0 := by
  apply cached_reads_zero
  intro input member
  exact checked_path_present first world cache input (coverage input member)

theorem pure_suffix_exact (first suffix : List (String × String)) (world : World)
    (cache : Bytes) (sound : Sound cache world) :
    (check suffix world (check first world cache).cache).accepted = true ↔
      ∀ input ∈ suffix, world input.1 = some input.2 :=
  check_exact suffix world _ (check_sound first world cache sound)

/-- A new requirement discovered during replay cannot be dropped from the final
projection even when its path was already read under another expectation. -/
theorem conflicting_suffix_rejected (first : List (String × String)) (world : World)
    (cache : Bytes) (sound : Sound cache world) (path left right : String)
    (actual : world path = some left) (different : left ≠ right) :
    (check [(path, right)] world (check first world cache).cache).accepted ≠ true := by
  intro accepted
  have exact := (pure_suffix_exact first [(path, right)] world cache sound).mp accepted
  have bad := exact (path, right) (by simp)
  rw [actual] at bad
  exact different (Option.some.inj bad)

/-- Cache reuse does not replace the existing domain/receiver/coverage predicate. -/
def admitWithCache (config : RootChild.Config) (parts : List RootChild.Contribution)
    (evidence : RootChild.Analysis) (world : World) (cache : Bytes) : Bool :=
  (evidence.candidate == config) && (evidence.contributions == parts) &&
    RootChild.domain config parts && (check (RootChild.inputs parts) world cache).accepted

theorem admission_same_world (config : RootChild.Config) (parts : List RootChild.Contribution)
    (evidence : RootChild.Analysis) (world : World) (cache : Bytes) (sound : Sound cache world) :
    admitWithCache config parts evidence world cache = RootChild.rootCheck config parts evidence world := by
  have same : (check (RootChild.inputs parts) world cache).accepted =
      (check (RootChild.inputs parts) world empty).accepted := by
    apply Bool.eq_iff_iff.mpr
    exact (check_exact _ _ _ sound).trans (fresh_exact _ _).symm
  simp only [admitWithCache, RootChild.rootCheck, same]

theorem joint_requirements_retained (config : RootChild.Config) (parts : List RootChild.Contribution)
    (evidence : RootChild.Analysis) (world : World) (cache : Bytes) (sound : Sound cache world)
    (accepted : admitWithCache config parts evidence world cache = true) :
    ∀ part ∈ parts, part.port = config.databasePort := by
  rw [admission_same_world _ _ _ _ _ sound] at accepted
  exact RootChild.requirements_retained _ _ _ _ accepted

theorem cached_parent_rejected (config : RootChild.Config) (parts : List RootChild.Contribution)
    (evidence : RootChild.Analysis) (world : World) (cache : Bytes) (sound : Sound cache world)
    (different : evidence.candidate ≠ config) :
    admitWithCache config parts evidence world cache ≠ true := by
  rw [admission_same_world _ _ _ _ _ sound]
  exact RootChild.cached_parent_rejected _ _ _ _ different

theorem fresh_after_callback_rejects_change (requirements : List (String × String))
    (after : World) (input : String × String) (member : input ∈ requirements)
    (changed : after input.1 ≠ some input.2) :
    (check requirements after empty).accepted = false :=
  changed_source_rejected requirements after input member changed

-- Same path, different expectations still fails despite requiring zero new I/O.
#guard !(check [("postgresql.json", "other")]
  (fun _ => some "original")
  (check [("postgresql.json", "original")] (fun _ => some "original") empty).cache).accepted
-- A previous callback's successful check is NOT a fresh return certificate.
#guard (check [("postgresql.json", "original")] (fun _ => some "changed")
  (check [("postgresql.json", "original")] (fun _ => some "original") empty).cache).accepted
#guard !(check [("postgresql.json", "original")] (fun _ => some "changed") empty).accepted

/-- A covered earlier pure check may be deferred into the complete final pass.
This is a semantic equivalence on actual source requirements, not a purity tag. -/
theorem defer_covered_check (early complete : List (String × String)) (world : World)
    (coverage : ∀ input ∈ early, input ∈ complete) :
    (check (early ++ complete) world empty).accepted =
      (check complete world empty).accepted := by
  apply Bool.eq_iff_iff.mpr
  rw [fresh_exact, fresh_exact]
  constructor
  · intro all input member
    exact all input (List.mem_append_right early member)
  · intro all input member
    rcases List.mem_append.mp member with early | final
    · exact all input (coverage input early)
    · exact all input final

private def complete : List (String × String) :=
  [("postgresql.json", "original"), ("override.ss", "original")]
private def early : List (String × String) := [("postgresql.json", "original")]
private def unchanged : World := fun _ => some "original"

/-- Small computed witness for the general composition law. The runtime's
88-path cut is separate observational evidence, not synthetic proof input. -/
theorem pure_tail_fixture_cost :
    (check early unchanged empty).reads +
      (check complete unchanged empty).reads = 3 ∧
    (check (early ++ complete) unchanged empty).reads = 2 := by decide

end YuanxuProof.Admission.ReturnWindows
