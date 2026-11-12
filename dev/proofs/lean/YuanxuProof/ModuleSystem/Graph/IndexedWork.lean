-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.SourceClosureWork
import YuanxuProof.ModuleSystem.Loading.IncrementalRoles
import LeanPoo.Functional.KeyIndex
import LeanPoo.Functional.GeneralizedGraph

/-! Work accounting over the existing executable HashSet traversal.
Counts name actual membership probes, adjacency bucket reads and emitted
edges. They do not assume constant-time hashing or certify source/POO reads. -/
namespace YuanxuProof.ModuleSystem.Graph.IndexedWork
open TestAdmission
open LeanPoo.Functional.Requirements

structure Work where
  discovery : IndexedDiscovery
  probes : Nat := 0
  buckets : Nat := 0
  edges : Nat := 0

def start (roots : List Nat) : Work := ⟨⟨⟨[], roots⟩, ∅⟩, 0, 0, 0⟩

def step (deps : Nat → List Nat) (state : Work) : Work :=
  match state.discovery.ordered.pending with
  | [] => state
  | owner :: rest =>
    if state.discovery.visited.contains owner then
      { state with
        discovery := { state.discovery with ordered := ⟨state.discovery.ordered.seen, rest⟩ }
        probes := state.probes + 1 }
    else
      -- One adjacency acquisition supplies both the transition and its count.
      -- Instrumentation must not call the producer again just for length.
      let children := deps owner
      ⟨⟨⟨owner :: state.discovery.ordered.seen, children ++ rest⟩,
          state.discovery.visited.insert owner⟩,
        state.probes + 1, state.buckets + 1, state.edges + children.length⟩

theorem step_projects_existing_discovery (deps : Nat → List Nat) (state : Work) :
    (step deps state).discovery = advanceIndexed deps state.discovery := by
  cases pending : state.discovery.ordered.pending with
  | nil => simp [step, advanceIndexed, pending]
  | cons owner rest =>
    by_cases present : state.discovery.visited.contains owner = true <;>
      simp [step, advanceIndexed, pending, Std.HashSet.mem_iff_contains, present]

def run (deps : Nat → List Nat) : Nat → Work → Work
  | 0, state => state
  | fuel + 1, state => run deps fuel (step deps state)

theorem projects_existing_discovery (deps : Nat → List Nat) (fuel : Nat) (state : Work) :
    (run deps fuel state).discovery = discoverIndexed deps fuel state.discovery := by
  induction fuel generalizing state with
  | zero => rfl
  | succ fuel ih =>
    rw [run, ih, step_projects_existing_discovery]
    rfl

theorem step_bucket_accounting (deps : Nat → List Nat) (state : Work) :
    (step deps state).buckets + state.discovery.ordered.seen.length =
      state.buckets + (step deps state).discovery.ordered.seen.length := by
  cases pending : state.discovery.ordered.pending with
  | nil => simp [step, pending]
  | cons owner rest =>
    by_cases present : state.discovery.visited.contains owner = true <;>
      simp [step, pending, present,
        Nat.add_comm, Nat.add_left_comm]

theorem bucket_accounting (deps : Nat → List Nat) (fuel : Nat) (state : Work) :
    (run deps fuel state).buckets + state.discovery.ordered.seen.length =
      state.buckets + (run deps fuel state).discovery.ordered.seen.length := by
  induction fuel generalizing state with
  | zero => rfl
  | succ fuel ih =>
    have first := step_bucket_accounting deps state
    have rest := ih (step deps state)
    simp only [run]
    omega

def Balanced (roots : Nat) (state : Work) : Prop :=
  state.probes + state.discovery.ordered.pending.length = roots + state.edges

theorem step_balanced (deps : Nat → List Nat) (roots : Nat) (state : Work)
    (before : Balanced roots state) : Balanced roots (step deps state) := by
  cases pending : state.discovery.ordered.pending with
  | nil => simpa [step, pending] using before
  | cons owner rest =>
    by_cases present : state.discovery.visited.contains owner = true
    · simpa [Balanced, step, pending, present,
        Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using before
    · simp only [Balanced, pending, List.length_cons] at before
      simp [Balanced, step, pending,
        present, List.length_append]
      omega

theorem run_balanced (deps : Nat → List Nat) (roots fuel : Nat) (state : Work)
    (before : Balanced roots state) : Balanced roots (run deps fuel state) := by
  induction fuel generalizing state with
  | zero => exact before
  | succ fuel ih => exact ih _ (step_balanced deps roots state before)

theorem completed_probe_count (deps : Nat → List Nat) (roots : List Nat) (fuel : Nat)
    (complete : (run deps fuel (start roots)).discovery.ordered.pending = []) :
    (run deps fuel (start roots)).probes =
      roots.length + (run deps fuel (start roots)).edges := by
  have balance := run_balanced deps roots.length fuel (start roots) (by simp [Balanced, start])
  simpa [Balanced, complete] using balance

theorem buckets_exactly_reached (deps : Nat → List Nat) (roots : List Nat) (fuel : Nat) :
    (run deps fuel (start roots)).buckets =
      (discoverIndexed deps fuel ⟨⟨[], roots⟩, ∅⟩).ordered.seen.length := by
  have counts := bucket_accounting deps fuel (start roots)
  simpa [start, projects_existing_discovery] using counts

theorem bucket_bound (deps : Nat → List Nat) (catalog roots : List Nat) (fuel : Nat)
    (rootsInside : ∀ root ∈ roots, root ∈ catalog)
    (edgesInside : ∀ owner ∈ catalog, ∀ child ∈ deps owner, child ∈ catalog) :
    (run deps fuel (start roots)).buckets ≤ catalog.length := by
  rw [buckets_exactly_reached]
  exact (indexed_discovery_visit_bound deps catalog roots fuel rootsInside edgesInside).2

-- Retain the frontier only over the same immutable dependency function.
-- Preserve unfinished work when another change arrives. Runtime ticket
-- checks remain owned by DependencyPublication.
def continueFrom (sealed : Work) (added : List Nat) : Work :=
  { sealed with discovery := { sealed.discovery with
      ordered := ⟨sealed.discovery.ordered.seen,
        sealed.discovery.ordered.pending ++ added⟩ } }

theorem continuation_preserves_pending (prior : Work) (added : List Nat) :
    (continueFrom prior added).discovery.ordered.pending =
      prior.discovery.ordered.pending ++ added := rfl

theorem continuation_balanced (roots : Nat) (prior : Work) (added : List Nat)
    (balanced : Balanced roots prior) :
    Balanced (roots + added.length) (continueFrom prior added) := by
  simp only [Balanced, continueFrom, List.length_append] at *
  omega

theorem continued_bucket_count (deps : Nat → List Nat) (fuel : Nat)
    (sealed : Work) (added : List Nat) :
    (run deps fuel (continueFrom sealed added)).buckets +
      sealed.discovery.ordered.seen.length =
    sealed.buckets + (run deps fuel (continueFrom sealed added)).discovery.ordered.seen.length :=
  bucket_accounting deps fuel (continueFrom sealed added)

theorem visited_owner_reads_no_bucket (deps : Nat → List Nat) (state : Work) (owner : Nat)
    (pending : state.discovery.ordered.pending = [owner])
    (visited : owner ∈ state.discovery.visited) :
    (step deps state).buckets = state.buckets ∧
      (step deps state).edges = state.edges := by
  simp [step, pending, visited]

-- The exact retained-owner index comes from LeanPoo. Filter only reached
-- reverse-index owners, without enumerating every certificate/catalog owner.
def retainedAffected (consumers : Nat → List Nat) (changed : List Nat) (fuel : Nat)
    {retained : List Nat} (index : KeyIndex retained) : List Nat :=
  (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.seen.filter index.contains

theorem retained_affected_exact
    (consumers : Nat → List Nat) (registered : Nat → Nat → Prop)
    (exactReverse : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed : List Nat) (fuel : Nat) {retained : List Nat} (index : KeyIndex retained)
    (complete : (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.pending = [])
    (owner : Nat) :
    owner ∈ retainedAffected consumers changed fuel index ↔
      Loading.IncrementalRoles.Affected registered (fun key => key ∈ changed) owner ∧
        owner ∈ retained := by
  simp only [retainedAffected, List.mem_filter, KeyIndex.contains_iff]
  rw [completed_indexed_discovery_exact consumers changed fuel complete,
    Loading.IncrementalRoles.reverse_index_reaches_exactly_affected
      consumers registered exactReverse changed owner]

-- Reuse the library's checked topological rank after an edge restriction.
-- The Module publisher still owns roster identity, owner admission and
-- independent live-state checks. This theorem grants no value certificate.
open LeanPoo.Functional.GeneralizedGraph in
theorem removed_edges_preserve_library_schedule
    {Key : Type} {Value : Key → Type} [DecidableEq Key]
    {before after : Declaration Key Value} (prior : Scheduled before)
    (edges : ∀ key dep, dep ∈ after.reads key → dep ∈ before.reads key)
    (known : ∀ key, (after.footprint key).unknown = false) :
    (prior.restrict edges known).order = prior.order ∧
      (prior.restrict edges known).resolver.rank = prior.resolver.rank := ⟨rfl, rfl⟩

open LeanPoo.Functional.GeneralizedGraph in
theorem new_edge_cannot_reuse_a_violated_rank
    {Key : Type} {Value : Key → Type} [DecidableEq Key]
    {before after : Declaration Key Value} (prior : Scheduled before)
    (key dep : Key) (added : dep ∈ after.reads key)
    (violated : ¬prior.resolver.rank dep < prior.resolver.rank key) :
    ∀ attempted : Scheduled after,
      attempted.resolver.rank = prior.resolver.rank → False := by
  intro attempted same
  have lower := attempted.edgeLower key dep added
  rw [same] at lower
  exact violated lower

private def scale : Bool :=
  let deps := fun owner => if owner = 0 then [] else [0]
  let sparse := run deps 2 (start [9999])
  let full := run deps 20000 (start (List.range 10000))
  let restarted := ((List.range 10000).map fun owner =>
    (run deps 2 (start [owner])).buckets).sum
  let cycle := run sharedCycle 8 (start [0])
  let reverse := fun owner =>
    if owner = 11 then [12] else if owner = 12 then [13] else
    if owner = 21 then [22] else []
  let first := run reverse 3 (start [11])
  let next := run reverse 4 (continueFrom first [11, 21])
  let pending := run reverse 1 (start [11])
  let mergedPending := run reverse 4 (continueFrom pending [21])
  let affected := retainedAffected reverse [11] 3 (KeyIndex.ofKeys (List.range 10000))
  sparse.discovery.ordered.pending.isEmpty && sparse.buckets == 2 &&
    sparse.probes == 2 && sparse.edges == 1 &&
    full.discovery.ordered.pending.isEmpty && full.buckets == 10000 &&
    full.probes == 19999 && full.edges == 9999 && restarted == 19999 &&
    cycle.discovery.ordered.pending.isEmpty && cycle.buckets == 4 && cycle.probes == 6 &&
    next.discovery.ordered.pending.isEmpty && first.buckets == 3 &&
    next.buckets == 5 && next.edges == 3 && next.probes == 6 &&
    mergedPending.discovery.ordered.pending.isEmpty && mergedPending.buckets == 5 &&
    mergedPending.probes == 5 &&
    affected == [13, 12, 11]

#eval if scale then "INDEXED-GRAPH-WORK-10000-OK" else "INDEXED-GRAPH-WORK-10000-FAIL"
#guard scale

-- Adversarial collisions preserve exact key membership. Probe counts above
-- do not bound the work inside a hash bucket under such a hash function.
private def collidingKeys : Bool :=
  letI : Hashable Nat := ⟨fun _ => 0⟩
  let index := KeyIndex.ofKeys [11, 21]
  index.contains 11 && index.contains 21 && !index.contains 31

#guard collidingKeys

end YuanxuProof.ModuleSystem.Graph.IndexedWork
