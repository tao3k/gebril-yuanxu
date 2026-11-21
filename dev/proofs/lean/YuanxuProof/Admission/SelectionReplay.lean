-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.CacheLookup
import YuanxuProof.Admission.IssuerProjection
namespace YuanxuProof.Admission.SelectionReplay
-- The runtime owner retains a value, not the verdict of an external-source check.
theorem cached_graph_keeps_value {Name Value Fault : Type} [DecidableEq Name]
    (entries : Name → Option Value) (key : Name) (value : Value)
    (build : Unit → Except Fault Value) (hit : entries key = some value) :
    LeanPoo.Functional.ConstructionCache.ensureLookup entries key build = (.ok value, entries) :=
  LeanPoo.Functional.ConstructionCache.ensureLookup_hit entries key value build hit

def firstError : List (Option Nat) → Option Nat
  | [] => none
  | none :: rest => firstError rest
  | some error :: _ => some error

/-- The closure consumes edges of the exact admitted record. A private table
handoff preserves the admission failure and the independent commit check. -/
theorem admitted_owner_edges_handoff {Record Edge Fault : Type}
    (admit : Except Fault Record) (edges : Record → List Edge)
    (lookup : Record → Record) (same : ∀ record, lookup record = record)
    (commit : List Edge → Except Fault (List Edge)) :
    (admit >>= fun record => commit (edges (lookup record))) =
    (admit >>= fun record => commit (edges record)) := by
  cases admit <;> simp [same]

/-- For the same pure parser, an unchanged source has the initially parsed
tags. Changed source must still be classified by the original parser. -/
theorem profile_reclassification_on_change {Source Tags : Type} [DecidableEq Source]
    (classify : Source → Tags) (original current : Source) :
    (if current = original then classify original else classify current) =
      classify current := by
  split
  next unchanged => rw [unchanged]
  next _ => rfl

/-- One runtime private operation, with no callback between the two issuance
queries. The second predicate's failure spelling is irrelevant: on failure the
first guard has already refused, and on success both see the same runtime state.
This licenses no reuse across a visitor, another record, or final replay. -/
theorem immediate_issuance_query_redundant (authentic : Bool)
    (unissued stale : Nat) (remaining : List (Option Nat)) :
    firstError ((if authentic then none else some unissued) ::
                (if authentic then none else some stale) :: remaining) =
      firstError ((if authentic then none else some unissued) :: remaining) := by
  cases authentic <;> rfl

-- Runtime preparation replay, runtime admission replay, then revision-only
-- policy inspection: no opaque callback or concurrent metadata writer.
-- Stable preparation is a source-correspondence premise, not a purity flag.
theorem stable_tail_redundant (prep admit policy : Option Nat) :
    firstError [prep, admit, policy, prep] = firstError [prep, admit, policy] := by
  cases prep <;> cases admit <;> cases policy <;> rfl

def observed (prep admit policy after : Option Nat) := firstError [prep, admit, policy, after]
theorem observer_keeps_original_tail (prep admit policy after : Option Nat) :
    observed prep admit policy after = firstError [prep, admit, policy, after] := rfl

theorem observer_tail_cannot_be_dropped :
    firstError [none, none, none, some 1] ≠ firstError [none, none, none] := by decide

theorem preflight_reordering_changes_diagnostic :
    firstError [some 1, some 2] ≠ firstError [some 2, some 1] := by decide

theorem work_reduction (guards : Nat) : 3 * guards = 2 * guards + guards := by omega

-- Elapsed cost has independent work, collection and scheduling terms. This
-- is an accounting model, not a theorem about the runtime collector.
def elapsedCost (traversal source collection wait : Nat) : Nat :=
  traversal + source + collection + wait

theorem matched_work_bound (before after source collection wait : Nat)
    (lessWork : after ≤ before) :
    elapsedCost after source collection wait ≤
      elapsedCost before source collection wait := by
  unfold elapsedCost
  omega

-- Fewer calls alone says nothing about GC placement or wall time.
theorem fewer_replays_can_be_slower :
    6 < 9 ∧ elapsedCost 6 8 45 0 > elapsedCost 9 8 0 0 := by decide

theorem remove_collection_for_matched_comparison (work source collection wait : Nat) :
    elapsedCost work source collection wait - collection = work + source + wait := by
  unfold elapsedCost
  omega

-- Gambit's exec-stats deducts its end sample and, for an interpreted thunk,
-- call-frame accounting. This is a signed VM account, not physical payload.
def vmAccount (start finish sample frame : Int) : Int := finish - start - sample - frame
theorem accounting_correction (start finish sample frame : Int) :
    vmAccount start finish sample frame + sample + frame = finish - start := by
  unfold vmAccount
  omega
theorem negative_account_is_not_zero : vmAccount 100 90 8 0 = -18 := by decide
def wallCpuResidual (wall cpu : Int) : Int := wall - cpu
theorem residual_reconstruction (wall cpu : Int) :
    wallCpuResidual wall cpu + cpu = wall := by unfold wallCpuResidual; omega
-- GC CPU is already part of process CPU; adding it again double-counts.
theorem gc_is_not_extra_cpu (work gc : Nat) : (work + gc) + gc = work + 2 * gc := by omega

-- Successful reads supply decoded ranges. A mismatched range still consumes
-- the rest of the port transcript, where a later decoder or I/O fault can win.
def equalDecodedChars : List Char → List Char → Bool
  | [], [] => true
  | a :: as, b :: bs => (a == b) && equalDecodedChars as bs
  | _, _ => false

theorem equalDecodedChars_eq (left right : List Char) :
    equalDecodedChars left right = (left == right) := by
  induction left generalizing right with
  | nil => cases right <;> rfl
  | cons a rest ih =>
    cases right with
    | nil => rfl
    | cons b tail => simp [equalDecodedChars, ih]

def checkDecodedRanges (equalRange : List Char → List Char → Bool) (eofAtExpectedLength : Bool) :
    Bool → List (Except Nat (List Char × List Char)) → Except Nat Bool
  | same, [] => .ok (same && eofAtExpectedLength)
  | _, .error failure :: _ => .error failure
  | same, .ok (read, expected) :: rest =>
    checkDecodedRanges equalRange eofAtExpectedLength (same && equalRange read expected) rest

theorem native_decoded_ranges_keep_eof_and_faults (same eofAtExpectedLength : Bool)
    (ranges : List (Except Nat (List Char × List Char))) :
    checkDecodedRanges equalDecodedChars eofAtExpectedLength same ranges =
      checkDecodedRanges (fun left right => left == right) eofAtExpectedLength same ranges := by
  have equal : equalDecodedChars = (fun left right => left == right) :=
    funext (fun left => funext (equalDecodedChars_eq left))
  rw [equal]

example : checkDecodedRanges equalDecodedChars false true
    [.ok (['a'], ['b']), .error 4] = .error 4 := rfl

theorem single_lookup_saves_hits (hits misses : Nat) :
    2 * hits + misses = (hits + misses) + hits := by omega
theorem cached_false_is_a_value {Name Fault : Type} [DecidableEq Name]
    (entries : Name → Option Bool) (key : Name) (build : Unit → Except Fault Bool)
    (hit : entries key = some false) :
    LeanPoo.Functional.ConstructionCache.ensureLookup entries key build = (.ok false, entries) :=
  LeanPoo.Functional.ConstructionCache.ensureLookup_hit entries key false build hit

-- Runtime dependency ownership belongs to gerbil.pkg; LeanPoo belongs to Lake.
-- Runtime issued-read, inheritance and declaration-index controls
-- cover finite roots, owned parent spines and complete C3 Type registration.
-- Warm metadata preparation uses LeanPoo lookupOr_present; a cleared cache
-- uses lookupOr_missing and still invokes runtime preparation. The Scheme
-- cache-branch/invalidation correspondence remains a runtime-test obligation.

-- A structural projection contains record identities, not receiver/key pairs.
-- Fuel bounds the executable model; IdentityDFS owns termination/coverage.
def replayOrder (edges : Nat → List Nat) : Nat → List Nat → List Nat → List Nat
  | 0, _, _ => []
  | _ + 1, [], _ => []
  | fuel + 1, node :: pending, seen =>
    if node ∈ seen then replayOrder edges fuel pending seen
    else node :: replayOrder edges fuel (edges node ++ pending) (node :: seen)

theorem topology_reuse_keeps_identity_order (saved live : Nat → List Nat)
    (samePayload : ∀ node, saved node = live node) (fuel : Nat)
    (roots seen : List Nat) :
    replayOrder saved fuel roots seen = replayOrder live fuel roots seen := by
  have equal : saved = live := funext samePayload
  rw [equal]

theorem same_root_does_not_certify_edges :
    replayOrder (fun _ => []) 3 [1] [] ≠
    replayOrder (fun n => if n = 1 then [2] else []) 3 [1] [] := by decide

theorem roots_are_ordered_not_a_set :
    replayOrder (fun _ => []) 3 [1, 2] [] ≠
    replayOrder (fun _ => []) 3 [2, 1] [] := by decide

-- Identical structure never licenses retaining an old successful verdict.
theorem topology_is_not_authentication :
    firstError [none, some 1, none] ≠ firstError [none, none, none] := by decide
theorem topology_is_not_final_currentness :
    firstError [none, none, some 2] ≠ firstError [none, none, none] := by decide

-- A fresh frame cannot inherit the mutable seen set from another invocation.
theorem sharing_seen_suppresses_delivery :
    replayOrder (fun _ => []) 2 [1] [] ≠
    replayOrder (fun _ => []) 2 [1] [1] := by decide

-- Edges are justified by the actual registry -> original closure -> payload
-- projection, not by a user's assertion that a cached topology is immutable.
theorem authenticated_edges_match_frozen
    (store : IssuerProjection.Store) (record : IssuerProjection.Record)
    (closure : Nat) (frozen : IssuerProjection.Frozen)
    (registered : store.registry record.token = some closure)
    (captured : store.environments closure = some frozen)
    (authentic : IssuerProjection.authenticate store record = true) :
    record.payload.dependencies = frozen.payload.dependencies := by
  by_cases presented : record.presented = some closure
  · simp [IssuerProjection.authenticate, registered, captured, presented] at authentic
    exact congrArg IssuedRead.Payload.dependencies authentic.1.2
  · simp [IssuerProjection.authenticate, registered, presented] at authentic

-- Only the selected closure is compared. No hypothesis forces an unselected
-- receiver/slot, and edges outside this finite closure can change arbitrarily.
theorem topology_reuse_on_selected_closure (vertices : List Nat)
    (saved live : Nat → List Nat)
    (closed : ∀ n ∈ vertices, ∀ child ∈ saved n, child ∈ vertices)
    (same : ∀ n ∈ vertices, saved n = live n)
    (fuel : Nat) (roots seen : List Nat)
    (within : ∀ n ∈ roots, n ∈ vertices) :
    replayOrder saved fuel roots seen = replayOrder live fuel roots seen := by
  induction fuel generalizing roots seen with
  | zero => rfl
  | succ fuel ih =>
    cases roots with
    | nil => rfl
    | cons n rest =>
      have member : n ∈ vertices := within n (by simp)
      have restWithin : ∀ x ∈ rest, x ∈ vertices := by
        intro x h; exact within x (by simp [h])
      by_cases visited : n ∈ seen
      · simp only [replayOrder, visited, ↓reduceIte]
        exact ih rest seen restWithin
      · simp only [replayOrder, visited, ↓reduceIte]
        rw [same n member]
        congr 1
        apply ih
        intro x h
        rcases List.mem_append.mp h with dep | pending
        · apply closed n member x
          rwa [same n member]
        · exact restWithin x pending

structure ReplayProjection where
  roots : List Nat
  order : List Nat
  deriving DecidableEq

-- A private runtime owner caches only this projection. Weak index eviction is
-- represented by none; construction/refresh never returns an admission verdict.
def obtainProjection (roots : List Nat) (cached : Option ReplayProjection)
    (build : List Nat → ReplayProjection) : ReplayProjection :=
  match cached with
  | none => build roots
  | some p => if p.roots = roots then p else build roots

theorem projection_hit (p : ReplayProjection) (build : List Nat → ReplayProjection) :
    obtainProjection p.roots (some p) build = p := by simp [obtainProjection]
theorem changed_roots_rebuild (roots : List Nat) (p : ReplayProjection)
    (build : List Nat → ReplayProjection) (different : p.roots ≠ roots) :
    obtainProjection roots (some p) build = build roots := by simp [obtainProjection, different]
theorem weak_eviction_rebuild (roots : List Nat) (build : List Nat → ReplayProjection) :
    obtainProjection roots none build = build roots := rfl

theorem projection_lookup_refines (roots : List Nat) (cached : Option ReplayProjection)
    (build : List Nat → ReplayProjection)
    (owned : ∀ p, cached = some p → p.roots = roots → p.order = (build roots).order) :
    (obtainProjection roots cached build).order = (build roots).order := by
  cases cached with
  | none => rfl
  | some p =>
    by_cases keySame : p.roots = roots
    · simpa [obtainProjection, keySame] using owned p rfl keySame
    · simp [obtainProjection, keySame]

def validationOrder (order : List Nat)
    (preflight visit tail : Nat → Option Nat) : Option Nat :=
  firstError (order.map preflight ++ order.map visit ++ order.map tail)

theorem reuse_preserves_first_diagnostic (roots : List Nat) (cached : Option ReplayProjection)
    (build : List Nat → ReplayProjection)
    (owned : ∀ p, cached = some p → p.roots = roots → p.order = (build roots).order)
    (preflight visit tail : Nat → Option Nat) :
    validationOrder (obtainProjection roots cached build).order preflight visit tail =
    validationOrder (build roots).order preflight visit tail := by
  rw [projection_lookup_refines roots cached build owned]

theorem receiver_frame_preserved (before after : List Nat) (receiver : Nat → Nat)
    (same : before = after) : before.map receiver = after.map receiver := by rw [same]

theorem structural_hit_still_checks_tail :
    validationOrder [1] (fun _ => none) (fun _ => none) (fun _ => some 2) = some 2 := rfl

-- Constructing a runtime cache owner must not introduce an open CLOS init hook
-- into authentication. Changed constructor metadata takes the original DFS.
def invokesCacheConstructor (hit constructorIdentityMatches : Bool) : Bool :=
  !hit && constructorIdentityMatches
theorem changed_constructor_uses_uncached_path (hit : Bool) :
    invokesCacheConstructor hit false = false := by simp [invokesCacheConstructor]

/-- Ordered shared metadata checks and their transitive POO write dependencies.
The support proof includes changes to issuance, route, presence and checker
identity. External sources and callbacks stay outside this group. -/
structure SharedChecks where
  owners : List Nat
  checks : (Nat → Nat) → List (Option Nat)
  covered : ∀ before after, (∀ owner ∈ owners, before owner = after owner) →
    checks before = checks after

/-- The registered POO reverse index maps a changed owner to its dependent
groups. This transition only visits the affected entries in the runtime model.
Here the function describes the resulting membership relation. -/
def affected (reverse : Nat → List Nat) (writes : List Nat) (group : Nat) : Prop :=
  ∃ owner ∈ writes, group ∈ reverse owner

instance (reverse : Nat → List Nat) (writes : List Nat) (group : Nat) :
    Decidable (affected reverse writes group) := by
  unfold affected
  infer_instance

def revoke (reverse : Nat → List Nat) (writes : List Nat)
    (valid : Nat → Bool) : Nat → Bool :=
  fun group => if affected reverse writes group then false else valid group

theorem dependent_group_revoked (reverse : Nat → List Nat) (writes : List Nat)
    (valid : Nat → Bool) (owner group : Nat)
    (changed : owner ∈ writes) (registered : group ∈ reverse owner) :
    revoke reverse writes valid group = false := by
  simp [revoke, show affected reverse writes group from ⟨owner, changed, registered⟩]

def supportMatches (group : SharedChecks) (issued live : Nat → Nat) : Prop :=
  ∀ owner ∈ group.owners, issued owner = live owner

/-- A surviving registration has the same read support, even after a callback
wrote other objects. The transition must publish the revocation with the write.
Completeness of native write notification remains a runtime premise. -/
theorem surviving_group_matches (shared : SharedChecks) (index : Nat → List Nat)
    (writes : List Nat) (valid : Nat → Bool) (group : Nat)
    (issued before after : Nat → Nat)
    (registered : ∀ owner ∈ shared.owners, group ∈ index owner)
    (old : valid group = true → supportMatches shared issued before)
    (unchanged : ∀ owner, owner ∉ writes → before owner = after owner)
    (hit : revoke index writes valid group = true) :
    supportMatches shared issued after := by
  have live : ¬ affected index writes group := by
    intro dirty
    simp [revoke, dirty] at hit
  have prior : valid group = true := by simpa [revoke, live] using hit
  intro owner member
  have outside : owner ∉ writes := by
    intro edited
    exact live ⟨owner, edited, registered owner member⟩
  exact (old prior owner member).trans (unchanged owner outside)

theorem firstError_append (left right : List (Option Nat)) :
    firstError (left ++ right) = (firstError left).or (firstError right) := by
  induction left with
  | nil => rfl
  | cons head tail ih => cases head <;> simp [firstError, ih, Option.or]

def verifyShared (closed : Bool) (valid : Bool) (shared : SharedChecks) (live : Nat → Nat) :
    List (Option Nat) :=
  if closed && valid then [] else shared.checks live

/-- Only an issued successful group with matching live support may disappear.
Keep both surrounding checks and the first diagnostic, including on a miss.
For an open window the original replay is used even with a matching group. -/
theorem indexed_replay_keeps_first_failure (closed valid : Bool)
    (shared : SharedChecks) (issued live : Nat → Nat)
    (earlier suffix : List (Option Nat))
    (approved : firstError (shared.checks issued) = none)
    (current : valid = true → supportMatches shared issued live) :
    firstError (earlier ++ verifyShared closed valid shared live ++ suffix) =
    firstError (earlier ++ shared.checks live ++ suffix) := by
  cases closed <;> cases valid <;> simp [verifyShared]
  have fixed : shared.checks issued = shared.checks live := shared.covered _ _ (current rfl)
  have clean : firstError (shared.checks live) = none := fixed ▸ approved
  simp [firstError_append, clean]

theorem open_window_keeps_checks (valid : Bool) (shared : SharedChecks) (live : Nat → Nat) :
    verifyShared false valid shared live = shared.checks live := rfl

theorem post_write_replay_keeps_first_failure (closed : Bool)
    (shared : SharedChecks) (index : Nat → List Nat) (writes : List Nat)
    (valid : Nat → Bool) (group : Nat) (issued before after : Nat → Nat)
    (earlier later : List (Option Nat))
    (approved : firstError (shared.checks issued) = none)
    (registered : ∀ owner ∈ shared.owners, group ∈ index owner)
    (old : valid group = true → supportMatches shared issued before)
    (unchanged : ∀ owner, owner ∉ writes → before owner = after owner) :
    firstError (earlier ++ verifyShared closed (revoke index writes valid group) shared after ++ later) =
      firstError (earlier ++ shared.checks after ++ later) :=
  indexed_replay_keeps_first_failure closed _ shared issued after earlier later approved
    (surviving_group_matches shared index writes valid group issued before after
      registered old unchanged)

/-- Work counts for one successful shared check at issuance and one indexed
validity lookup at each later replay. Count local checks and revocation
separately. No elapsed-time claim follows from this count. -/
def indexedSharedWork (width boundaries : Nat) : Nat := width + boundaries

theorem indexed_shared_work_saves_repeated_visits (width boundaries : Nat)
    (wide : 2 ≤ width) (repeated : 2 ≤ boundaries) :
    indexedSharedWork width boundaries ≤ width * boundaries := by
  unfold indexedSharedWork
  have row := Nat.mul_le_mul_right boundaries wide
  have column := Nat.mul_le_mul_left (width - 2) repeated
  have bound : (2 + (width - 2)) * boundaries = width * boundaries := by
    congr 1
    omega
  rw [Nat.add_mul] at bound
  omega

example : indexedSharedWork 916 (5 * 10000) = 50916 ∧
    916 * (5 * 10000) = 45800000 := by decide

-- An affected, effectful write must expose the original stale diagnostic.
private def mutationControl : SharedChecks where
  owners := [7]
  checks := fun versions => [if versions 7 = 0 then none else some 12]
  covered := by
    intro before after same
    rw [same 7 (by simp)]

example :
    let index := fun owner => if owner = 7 then [1] else []
    let live := fun owner => if owner = 7 then 1 else 0
    let valid := revoke index [7] (fun _ => true)
    firstError (verifyShared true (valid 1) mutationControl live) = some 12 ∧
    firstError (verifyShared true (valid 2) mutationControl (fun _ => 0)) = none ∧
    firstError (verifyShared false true mutationControl live) = some 12 ∧
    firstError ([some 3] ++ verifyShared true (valid 1) mutationControl live) = some 3 ∧
    firstError (verifyShared true (revoke (fun _ => []) [7] (fun _ => true) 1)
      mutationControl live) = none := by decide

/-- The native write index currently advances object revisions for registered
edits. Slot population and edits to the presented token have separate
observability, so a matching object revision cannot certify these facts. -/
structure ReadState where
  revision : Nat
  occupied : Bool
  issued : Bool

def readCurrent (capturedRevision : Nat) (expectedOccupied : Bool) (live : ReadState) : Bool :=
  live.issued && (capturedRevision == live.revision) && (expectedOccupied == live.occupied)

theorem revision_only_cannot_decide_cache_miss
    (decideCurrent : Nat → Bool) :
    ¬ ∀ live, decideCurrent live.revision = readCurrent 0 false live := by
  intro same
  have cold := same ⟨0, false, true⟩
  have warm := same ⟨0, true, true⟩
  change decideCurrent 0 = true at cold
  change decideCurrent 0 = false at warm
  simp [cold] at warm

theorem revision_only_cannot_decide_issuance
    (decideCurrent : Nat → Bool) :
    ¬ ∀ live, decideCurrent live.revision = readCurrent 0 true live := by
  intro same
  have issued := same ⟨0, true, true⟩
  have changed := same ⟨0, true, false⟩
  simp [readCurrent] at issued changed
  simp [issued] at changed

end YuanxuProof.Admission.SelectionReplay
