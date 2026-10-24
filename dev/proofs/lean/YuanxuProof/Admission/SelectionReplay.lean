-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.CacheLookup
import YuanxuProof.Admission.IssuerProjection
namespace YuanxuProof.Admission.SelectionReplay
def declaredPooRevision : String := "247a7eb8a40dca0843956da2cf93eb5b36dbdd62"
def quintSourceDigest : String := "sha256:83a2b605e11bdad9f8689c58a9a9bd37a2dadb67dec025e81d47b3ce6b915d13"

-- The native owner retains a value, not the verdict of an external-source check.
theorem cached_graph_keeps_value {Name Value Fault : Type} [DecidableEq Name]
    (entries : Name → Option Value) (key : Name) (value : Value)
    (build : Unit → Except Fault Value) (hit : entries key = some value) :
    LeanPoo.Functional.ConstructionCache.ensureLookup entries key build = (.ok value, entries) :=
  LeanPoo.Functional.ConstructionCache.ensureLookup_hit entries key value build hit

def firstError : List (Option Nat) → Option Nat
  | [] => none
  | none :: rest => firstError rest
  | some error :: _ => some error

-- Native preparation replay, native admission replay, then revision-only
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

theorem single_lookup_saves_hits (hits misses : Nat) :
    2 * hits + misses = (hits + misses) + hits := by omega
theorem cached_false_is_a_value {Name Fault : Type} [DecidableEq Name]
    (entries : Name → Option Bool) (key : Name) (build : Unit → Except Fault Bool)
    (hit : entries key = some false) :
    LeanPoo.Functional.ConstructionCache.ensureLookup entries key build = (.ok false, entries) :=
  LeanPoo.Functional.ConstructionCache.ensureLookup_hit entries key false build hit

def topologySourceDigest : String := "sha256:711666f5afe6d73d34cc59caf536311b2eb9907fa675ef049dd0720e13993773"

def projectionObjectDigest : String := "sha256:bdba1ca6c9d0df33833c39d951961c73b2f10d4b6719120afd2a79b099391d83"

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

-- A private native owner caches only this projection. Weak index eviction is
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

-- Constructing a native cache owner must not introduce an open CLOS init hook
-- into authentication. Changed constructor metadata takes the original DFS.
def invokesCacheConstructor (hit constructorIdentityMatches : Bool) : Bool :=
  !hit && constructorIdentityMatches
theorem changed_constructor_uses_uncached_path (hit : Bool) :
    invokesCacheConstructor hit false = false := by simp [invokesCacheConstructor]
end YuanxuProof.Admission.SelectionReplay
