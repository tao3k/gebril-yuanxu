-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.CacheLookup
import LeanPoo.Functional.ContextSlot
import YuanxuProof.Admission.Source

/-! Source bytes, POO values and admission certificates are different caches.
The filesystem is an actual read function, not a free revision oracle.
Stability inside a pure window and complete observation remain runtime premises. -/
namespace YuanxuProof.Admission.SourceWindows
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

/-- Ordered mismatch projection. Reusing bytes does not sort, deduplicate or
collapse requirements, and is not valid after an unobserved world change. I/O
exceptions and Scheme callback extraction remain native bridge obligations. -/
def firstIssue (requirements : List (String × String)) (world : World) : Option String :=
  match requirements with
  | [] => none
  | (path, expected) :: rest =>
    if world path == some expected then firstIssue rest world else some path

def checkedIssue (requirements : List (String × String)) (world : World)
    (cache : Bytes) : Option String :=
  match requirements with
  | [] => none
  | (path, expected) :: rest =>
    let loaded := fetch cache world path
    if loaded.1 == some expected then checkedIssue rest world loaded.2 else some path

theorem pure_window_preserves_first_issue (requirements : List (String × String))
    (world : World) (cache : Bytes) (sound : Sound cache world) :
    checkedIssue requirements world cache = firstIssue requirements world := by
  induction requirements generalizing cache with
  | nil => rfl
  | cons input rest ih =>
    rcases input with ⟨path, expected⟩
    simp only [checkedIssue, firstIssue, fetch_value cache world path sound]
    split
    · exact ih _ (fetch_sound cache world path sound)
    · rfl

/-- Ordered policy rows are already owned by the directory publication. A world
fact can encode listing membership, kind or exact content. -/
def agreesOn (requirements : List (String × String)) (left right : World) : Prop :=
  ∀ row ∈ requirements, left row.1 = right row.1

theorem firstIssue_agreesOn (requirements : List (String × String)) (left right : World)
    (same : agreesOn requirements left right) :
    firstIssue requirements left = firstIssue requirements right := by
  induction requirements with
  | nil => rfl
  | cons row rest ih =>
    obtain ⟨path, expected⟩ := row
    simp only [firstIssue, same (path, expected) (List.mem_cons_self ..)]
    split
    · exact ih fun row member => same row (List.mem_cons_of_mem _ member)
    · rfl

theorem firstIssue_append (left right : List (String × String)) (world : World) :
    firstIssue (left ++ right) world = (firstIssue left world).or (firstIssue right world) := by
  induction left with
  | nil => rfl
  | cons row rest ih =>
    obtain ⟨path, expected⟩ := row
    simp only [List.cons_append, firstIssue]
    split <;> simp_all

/-- A locally observed request cannot decide a global policy that can fail at an
unobserved path. Construct the alternative world by changing just that fact. -/
theorem missing_fact_precludes_global_decision
    (localPolicy globalPolicy : List (String × String)) (world : World)
    (path expected : String)
    (unseen : ∀ row ∈ localPolicy, row.1 ≠ path)
    (required : (path, expected) ∈ globalPolicy)
    (accepted : (check globalPolicy world empty).accepted = true) :
    ∃ changed : World, agreesOn localPolicy world changed ∧
      (check globalPolicy world empty).accepted ≠ (check globalPolicy changed empty).accepted := by
  let changed : World := fun queried => if queried = path then none else world queried
  refine ⟨changed, ?_, ?_⟩
  · intro row member
    simp [changed, unseen row member]
  · rw [accepted, changed_source_rejected globalPolicy changed (path, expected) required]
    · decide
    · simp [changed]

structure DirectoryGeneration where
  authority : Nat
  revision : Nat
  deriving DecidableEq

/-- Indexed by the exact ordered policy. The summary is computed at publication;
it is not evidence that a later filesystem observation is still current. -/
structure DirectoryCut (requirements : List (String × String)) where
  generation : DirectoryGeneration
  snapshot : World
  issue : Option String
  summarized : issue = firstIssue requirements snapshot

def DirectoryCut.use {requirements : List (String × String)}
    (cut : DirectoryCut requirements) (active : DirectoryGeneration) : Option (Option String) :=
  if active = cut.generation then some cut.issue else none

theorem DirectoryCut.use_exact {requirements : List (String × String)}
    (cut : DirectoryCut requirements) (active : DirectoryGeneration) (live : World)
    (authority : active = cut.generation → agreesOn requirements cut.snapshot live) :
    cut.use active = if active = cut.generation then some (firstIssue requirements live) else none := by
  by_cases current : active = cut.generation
  · simp [DirectoryCut.use, current, cut.summarized,
      firstIssue_agreesOn requirements _ _ (authority current)]
  · simp [DirectoryCut.use, current]

theorem DirectoryCut.reject_stale {requirements : List (String × String)}
    (cut : DirectoryCut requirements) (active : DirectoryGeneration)
    (stale : active ≠ cut.generation) : cut.use active = none := by
  simp [DirectoryCut.use, stale]

theorem DirectoryCut.reject_other_authority {requirements : List (String × String)}
    (cut : DirectoryCut requirements) (active : DirectoryGeneration)
    (different : active.authority ≠ cut.generation.authority) : cut.use active = none := by
  exact cut.reject_stale active (fun same => different (congrArg DirectoryGeneration.authority same))

/-- A controlled edit can carry unaffected ordered summaries into a new cut.
The producer must establish both frame conditions in the new world. -/
theorem repair_firstIssue (leading edited trailing : List (String × String))
    (old live : World) (before : agreesOn leading old live) (after : agreesOn trailing old live) :
    firstIssue (leading ++ (edited ++ trailing)) live =
      (firstIssue leading old).or ((firstIssue edited live).or (firstIssue trailing old)) := by
  rw [firstIssue_append, firstIssue_append, ← firstIssue_agreesOn leading old live before,
    ← firstIssue_agreesOn trailing old live after]

/-- Extracted from the actual context procedure: only native `void` selects
`identity`. Every other procedure is opaque, including normal and exceptional
resumption. This is not a caller-supplied purity annotation. -/
inductive ContextStep where
  | identity
  | opaque (after : World)

def contextWorld (step : ContextStep) (before : World) : World :=
  match step with
  | .identity => before
  | .opaque after => after

def contextBytes (step : ContextStep) (before : Bytes) : Bytes :=
  match step with
  | .identity => before
  | .opaque _ => empty

theorem context_resume_sound (step : ContextStep) (world : World) (cache : Bytes)
    (sound : Sound cache world) :
    Sound (contextBytes step cache) (contextWorld step world) := by
  cases step with
  | identity => exact sound
  | «opaque» after => exact empty_sound after

theorem context_resume_checks_all (step : ContextStep) (world : World) (cache : Bytes)
    (sound : Sound cache world) (requirements : List (String × String)) :
    (check requirements (contextWorld step world) (contextBytes step cache)).accepted = true ↔
      ∀ input ∈ requirements, contextWorld step world input.1 = some input.2 :=
  check_exact requirements _ _ (context_resume_sound step world cache sound)

theorem context_resume_preserves_first_issue (step : ContextStep) (world : World)
    (cache : Bytes) (sound : Sound cache world) (requirements : List (String × String)) :
    checkedIssue requirements (contextWorld step world) (contextBytes step cache) =
      firstIssue requirements (contextWorld step world) :=
  pure_window_preserves_first_issue requirements _ _ (context_resume_sound step world cache sound)

-- An effect may modify the init source for one observation window and
-- restore it before the next. Observing the same path in every other
-- window cannot certify the omitted checkpoint.
def rootWindowsCurrent (worlds : Nat → World) (windows : List Nat)
    (path expected : String) : Bool :=
  windows.all fun window => decide (worlds window path = some expected)

theorem omitted_effect_window_can_hide_root_edit (observed required : List Nat)
    (omitted : Nat) (path expected : String)
    (notObserved : omitted ∉ observed) (needed : omitted ∈ required) :
    ∃ stable changed : Nat → World,
      (∀ window ∈ observed, stable window = changed window) ∧
      rootWindowsCurrent stable required path expected = true ∧
      rootWindowsCurrent changed required path expected = false := by
  refine ⟨fun _ _ => some expected,
    fun window queried => if window = omitted ∧ queried = path then none else some expected,
    ?_, ?_, ?_⟩
  · intro window member
    have different : window ≠ omitted := fun eq => notObserved (eq ▸ member)
    funext queried
    simp [different]
  · simp [rootWindowsCurrent]
  · apply Bool.eq_false_iff.mpr
    intro current
    have claim := List.all_eq_true.mp current omitted needed
    simp at claim

/-- A positive byte observation is produced only by a regular-file read. A
second lookup of that same kind in the stable window adds no requirement.
The native bridge keeps the original double lookup for open observers. -/
theorem positive_bytes_imply_kind (bytes : Option String) (expected : String) :
    (bytes.isSome && (bytes == some expected)) = (bytes == some expected) := by
  cases bytes with
  | none => rfl
  | some actual => simp

/-- Sharing filesystem bytes cannot collapse two independently enrolled
requirements, even when their path and expected-text lengths agree. -/
theorem conflicting_requirements_rejected
    (requirements : List (String × String)) (world : World) (cache : Bytes)
    (sound : Sound cache world) (path left right : String)
    (first : (path, left) ∈ requirements) (second : (path, right) ∈ requirements)
    (different : left ≠ right) :
    (check requirements world cache).accepted = false := by
  cases accepted : (check requirements world cache).accepted with
  | false => rfl
  | true =>
    have exactChecks := (check_exact requirements world cache sound).mp accepted
    have same : some left = some right :=
      (exactChecks (path, left) first).symm.trans (exactChecks (path, right) second)
    exact False.elim (different (Option.some.inj same))

-- A same-cardinality, same-path, same-length projection cannot distinguish
-- these requirements. Neither fact establishes expected-source equivalence.
#guard "5432".length == "5440".length
#guard (check [("config.ss", "5432"), ("config.ss", "5440")]
  (fun _ => some "5432") empty).accepted == false

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

-- Gerbil read-substring overwrites the returned prefix. The old suffix is
-- never a source observation. EOF and later decoder errors remain visible.
inductive TextRead (CharValue : Type) where
  | chunk (chunkChars : List CharValue)
  | failed (cause : Nat)

def overwritePrefix (chunkChars previous : List CharValue) : List CharValue :=
  chunkChars ++ previous.drop chunkChars.length

theorem overwritten_prefix_exact (chunkChars previous : List CharValue) :
    (overwritePrefix chunkChars previous).take chunkChars.length = chunkChars := by
  simp [overwritePrefix]

def compareChunk [BEq CharValue] (expected chunkChars : List CharValue) (offset : Nat)
    (matching : Bool) : Bool :=
  matching && (chunkChars == (expected.drop offset).take chunkChars.length)

def scanText [BEq CharValue] (expected : List CharValue) :
    List (TextRead CharValue) → Nat → Bool → Except Nat (Bool × Nat)
  | [], offset, matching => .ok (matching && (offset == expected.length), offset)
  | .failed cause :: _, _, _ => .error cause
  | .chunk chunkChars :: remaining, offset, matching =>
      scanText expected remaining (offset + chunkChars.length)
        (compareChunk expected chunkChars offset matching)

def scanWithScratch [BEq CharValue] (expected : List CharValue) :
    List (TextRead CharValue) → List CharValue → Nat → Bool → Except Nat (Bool × Nat)
  | [], _, offset, matching => .ok (matching && (offset == expected.length), offset)
  | .failed cause :: _, _, _, _ => .error cause
  | .chunk chunkChars :: remaining, scratch, offset, matching =>
      let updated := overwritePrefix chunkChars scratch
      scanWithScratch expected remaining updated (offset + chunkChars.length)
        (compareChunk expected (updated.take chunkChars.length) offset matching)

theorem reusable_scratch_preserves_text_check [BEq CharValue]
    (expected : List CharValue) (reads : List (TextRead CharValue))
    (scratch : List CharValue) (offset : Nat) (matching : Bool) :
    scanWithScratch expected reads scratch offset matching = scanText expected reads offset matching := by
  induction reads generalizing scratch offset matching with
  | nil => rfl
  | cons read remaining ih =>
    cases read with
    | failed => rfl
    | chunk chunkChars => simp only [scanWithScratch, scanText, overwritten_prefix_exact, ih]

-- A mismatch must not suppress a later I/O failure, and bytes left in a
-- reused buffer cannot make a truncated file match a longer declaration.
example : scanWithScratch [1, 2] [.chunk [9], .failed 7] [1, 2] 0 true = .error 7 := rfl
example : scanWithScratch [1, 2] [.chunk [1]] [1, 2] 0 true = .ok (false, 1) := rfl

/-- A replay captures the end of the existing ordered evidence before calling
any observer. Reentrant enrollment can extend the sequence, but the new
entries belong to the next replay. -/
theorem appended_observations_outside_replay {Observation : Type}
    (captured appended : List Observation) :
    (captured ++ appended).take captured.length = captured := by
  simp

theorem ordered_collection_matches_reversal {Observation : Type}
    (newestFirst : List Observation) (entry : Observation) :
    (entry :: newestFirst).reverse = newestFirst.reverse ++ [entry] := by
  simp

end YuanxuProof.Admission.SourceWindows
