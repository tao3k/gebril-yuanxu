-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.Cache
import Std.Data.HashSet.Lemmas

/-! A demand worklist over one immutable source dependency function. This is
an algorithm model, not a proof that the Scheme reader discovers every import.
Sources mean observed reader dependencies, not configuration-policy edges. -/
namespace YuanxuProof.ModuleSystem.Graph.TestAdmission

def quintSourceDigest : String :=
  "sha256:a6fbd0cbb215fb72a5bcb3faa939e537e2af15920c2eeb48654ff16bdcadf3e8"

structure Discovery (Node : Type) where
  seen : List Node
  pending : List Node
  deriving DecidableEq, Repr

def advance [DecidableEq Node] (dependencies : Node → List Node)
    (state : Discovery Node) : Discovery Node :=
  match state.pending with
  | [] => state
  | node :: rest =>
    if node ∈ state.seen then ⟨state.seen, rest⟩
    else ⟨node :: state.seen, dependencies node ++ rest⟩

def discover [DecidableEq Node] (dependencies : Node → List Node) :
    Nat → Discovery Node → Discovery Node
  | 0, state => state
  | fuel + 1, state => discover dependencies fuel (advance dependencies state)

def Inside (region : Node → Prop) (state : Discovery Node) : Prop :=
  (∀ node ∈ state.seen, region node) ∧ (∀ node ∈ state.pending, region node)

theorem advance_stays_inside [DecidableEq Node]
    (dependencies : Node → List Node) (region : Node → Prop)
    (closed : ∀ node, region node → ∀ child ∈ dependencies node, region child)
    (state : Discovery Node) (inside : Inside region state) :
    Inside region (advance dependencies state) := by
  rcases state with ⟨seen, pending⟩
  rcases inside with ⟨seenInside, pendingInside⟩
  cases pending with
  | nil => exact ⟨seenInside, pendingInside⟩
  | cons node rest =>
    have nodeInside := pendingInside node (by simp)
    have restInside : ∀ child ∈ rest, region child :=
      fun child member => pendingInside child (by simp [member])
    by_cases visited : node ∈ seen
    · simpa [advance, visited, Inside] using And.intro seenInside restInside
    · constructor
      · intro child member
        simp only [advance, visited, ↓reduceIte] at member
        rcases List.mem_cons.mp member with equal | previous
        · exact equal ▸ nodeInside
        · exact seenInside child previous
      · intro child member
        simp only [advance, visited, ↓reduceIte] at member
        rcases List.mem_append.mp member with dependency | previous
        · exact closed node nodeInside child dependency
        · exact restInside child previous

theorem discover_stays_inside [DecidableEq Node]
    (dependencies : Node → List Node) (region : Node → Prop)
    (closed : ∀ node, region node → ∀ child ∈ dependencies node, region child)
    (fuel : Nat) (state : Discovery Node) (inside : Inside region state) :
    Inside region (discover dependencies fuel state) := by
  induction fuel generalizing state with
  | zero => exact inside
  | succ fuel ih => exact ih _ (advance_stays_inside dependencies region closed state inside)

/-- Identical ordered rows on a forward-closed region preserve the whole
worklist trace. Set-equivalent rows alone do not imply the same order. -/
theorem discover_agrees_inside [DecidableEq Node]
    (prior next : Node → List Node) (region : Node → Prop)
    (closed : ∀ node, region node → ∀ child ∈ prior node, region child)
    (frame : ∀ node, region node → next node = prior node)
    (fuel : Nat) (state : Discovery Node) (inside : Inside region state) :
    discover next fuel state = discover prior fuel state := by
  induction fuel generalizing state with
  | zero => rfl
  | succ fuel ih =>
    have step : advance next state = advance prior state := by
      rcases state with ⟨seen, pending⟩
      cases pending with
      | nil => rfl
      | cons node rest =>
        have row := frame node (inside.2 node (by simp))
        simp [advance, row]
    simp only [discover, step]
    exact ih _ (advance_stays_inside prior region closed state inside)

theorem same_neighbors_can_change_discovery_order :
    let prior (node : Nat) := if node = 0 then [1, 2] else []
    let next (node : Nat) := if node = 0 then [2, 1] else []
    (∀ node child, child ∈ prior node ↔ child ∈ next node) ∧
      (discover prior 3 ⟨[], [0]⟩).seen ≠ (discover next 3 ⟨[], [0]⟩).seen := by
  dsimp only
  constructor
  · intro node child
    by_cases root : node = 0
    · simp [root, or_comm]
    · simp [root]
  · decide

inductive Demanded (dependencies : Node → List Node) (roots : List Node) : Node → Prop
  | root (node : Node) : node ∈ roots → Demanded dependencies roots node
  | dependency (parent child : Node) : Demanded dependencies roots parent →
      child ∈ dependencies parent → Demanded dependencies roots child

/-- The row projection used by a point request. The proof below requires the
admitted region to include every successor of each reached owner. -/
def admittedRows (dependencies : Node → List Node) (admitted : Node → Bool)
    (owner : Node) : List Node :=
  if admitted owner then dependencies owner else []

theorem admitted_rows_reach_exact (dependencies : Node → List Node)
    (admitted : Node → Bool) (roots : List Node)
    (rootAdmitted : ∀ node ∈ roots, admitted node = true)
    (closed : ∀ parent, admitted parent = true →
      ∀ child ∈ dependencies parent, admitted child = true)
    (node : Node) :
    Demanded (admittedRows dependencies admitted) roots node ↔
      Demanded dependencies roots node := by
  constructor
  · intro path
    induction path with
    | root owner member => exact .root owner member
    | dependency parent child _ edge path =>
      cases present : admitted parent with
      | false => simp [admittedRows, present] at edge
      | true => exact .dependency parent child path (by simpa [admittedRows, present] using edge)
  · intro path
    have lift : ∀ owner, Demanded dependencies roots owner →
        admitted owner = true ∧ Demanded (admittedRows dependencies admitted) roots owner := by
      intro owner reached
      induction reached with
      | root owner member => exact ⟨rootAdmitted owner member, .root owner member⟩
      | dependency parent child _ edge ih =>
        exact ⟨closed parent ih.1 child edge,
          .dependency parent child ih.2 (by simpa [admittedRows, ih.1] using edge)⟩
    exact (lift node path).2

/-- SCC membership is mutual reachability. Once the selected rows form a
forward-closed region, an SCC query there agrees with the whole graph. -/
theorem admitted_rows_component_exact (dependencies : Node → List Node)
    (admitted : Node → Bool) (left right : Node)
    (leftAdmitted : admitted left = true) (rightAdmitted : admitted right = true)
    (closed : ∀ parent, admitted parent = true →
      ∀ child ∈ dependencies parent, admitted child = true) :
    (Demanded (admittedRows dependencies admitted) [left] right ∧
      Demanded (admittedRows dependencies admitted) [right] left) ↔
    (Demanded dependencies [left] right ∧ Demanded dependencies [right] left) :=
  and_congr
    (admitted_rows_reach_exact dependencies admitted [left] (by simpa) closed right)
    (admitted_rows_reach_exact dependencies admitted [right] (by simpa) closed left)

/-- Cutting the provider of a two-owner cycle loses the path back to the
requested owner, even though the requested row itself remains exact. -/
theorem incomplete_rows_can_break_cycle :
    let dependencies := fun (owner : Bool) => [!owner]
    Demanded dependencies [false] true ∧ Demanded dependencies [true] false ∧
      ¬ Demanded (admittedRows dependencies not) [true] false := by
  dsimp only
  refine ⟨.dependency false true (.root false (by simp)) (by simp),
    .dependency true false (.root true (by simp)) (by simp), ?_⟩
  have onlyRoot (node : Bool)
      (path : Demanded (admittedRows (fun owner => [!owner]) not) [true] node) :
      node = true := by
    induction path with
    | root owner member => simpa using member
    | dependency parent child _ edge ih => simp [admittedRows, ih] at edge
  intro path
  exact Bool.noConfusion (onlyRoot false path)

/-- Ordinary scope demand uses its own root. Full certification still uses the
entire selection. An effective Feature decision retains the full graph. -/
def scopeRoots (roots : List Node) (target : Node) (hasFeatureDecisions : Bool) :
    List Node :=
  if hasFeatureDecisions then roots else [target]

theorem plain_scope_demand_is_within_full_selection
    (dependencies : Node → List Node) (roots : List Node) (target node : Node)
    (selected : target ∈ roots)
    (reached : Demanded dependencies (scopeRoots roots target false) node) :
    Demanded dependencies roots node := by
  change Demanded dependencies [target] node at reached
  induction reached with
  | root node member =>
    have equal : node = target := by simpa using member
    exact .root node (equal ▸ selected)
  | dependency parent child _ edge admitted =>
    exact .dependency parent child admitted edge

theorem feature_scope_demand_preserves_full_selection (roots : List Node) (target : Node) :
    scopeRoots roots target true = roots := rfl

theorem plain_scope_demand_is_within_auto_extension
    (dependencies : Node → List Node) (roots : List Node) (target node : Node)
    (reached : Demanded dependencies (scopeRoots roots target false) node) :
    Demanded dependencies (roots ++ [target]) node :=
  plain_scope_demand_is_within_full_selection dependencies (roots ++ [target])
    target node (by simp) reached

theorem every_discovered_node_is_demanded [DecidableEq Node]
    (dependencies : Node → List Node) (roots : List Node) (fuel : Nat) :
    ∀ node ∈ (discover dependencies fuel ⟨[], roots⟩).seen,
      Demanded dependencies roots node := by
  have inside : Inside (Demanded dependencies roots) (⟨[], roots⟩ : Discovery Node) := by
    constructor
    · simp
    · exact fun node member => Demanded.root node member
  exact (discover_stays_inside dependencies (Demanded dependencies roots)
    (fun parent demanded child member => Demanded.dependency parent child demanded member)
    fuel _ inside).1

def Scheduled (state : Discovery Node) (node : Node) : Prop :=
  node ∈ state.seen ∨ node ∈ state.pending

theorem advance_retains_scheduled [DecidableEq Node]
    (dependencies : Node → List Node) (state : Discovery Node) (node : Node)
    (scheduled : Scheduled state node) : Scheduled (advance dependencies state) node := by
  rcases state with ⟨seen, pending⟩
  cases pending with
  | nil => exact scheduled
  | cons next rest =>
    by_cases visited : next ∈ seen
    · simp only [advance, visited, ↓reduceIte, Scheduled] at scheduled ⊢
      rcases scheduled with old | queued
      · exact Or.inl old
      · rcases List.mem_cons.mp queued with same | tail
        · exact Or.inl (same ▸ visited)
        · exact Or.inr tail
    · simp only [advance, visited, ↓reduceIte, Scheduled] at scheduled ⊢
      rcases scheduled with old | queued
      · exact Or.inl (by simp [old])
      · rcases List.mem_cons.mp queued with same | tail
        · exact Or.inl (by simp [same])
        · exact Or.inr (List.mem_append.mpr (Or.inr tail))

def Covers (dependencies : Node → List Node) (roots : List Node)
    (state : Discovery Node) : Prop :=
  (∀ root ∈ roots, Scheduled state root) ∧
  (∀ node ∈ state.seen, ∀ child ∈ dependencies node, Scheduled state child)

theorem advance_preserves_coverage [DecidableEq Node]
    (dependencies : Node → List Node) (roots : List Node) (state : Discovery Node)
    (covers : Covers dependencies roots state) :
    Covers dependencies roots (advance dependencies state) := by
  constructor
  · exact fun root member => advance_retains_scheduled dependencies state root (covers.1 root member)
  · rcases state with ⟨seen, pending⟩
    cases pending with
    | nil => exact covers.2
    | cons next rest =>
      by_cases visited : next ∈ seen
      · intro node member child dependency
        simp only [advance, visited, ↓reduceIte] at member
        exact advance_retains_scheduled dependencies _ child (covers.2 node member child dependency)
      · intro node member child dependency
        simp only [advance, visited, ↓reduceIte] at member
        rcases List.mem_cons.mp member with same | old
        · subst node
          exact Or.inr (by simp [advance, visited, dependency])
        · exact advance_retains_scheduled dependencies _ child (covers.2 node old child dependency)

theorem discover_preserves_coverage [DecidableEq Node]
    (dependencies : Node → List Node) (roots : List Node) (fuel : Nat)
    (state : Discovery Node) (covers : Covers dependencies roots state) :
    Covers dependencies roots (discover dependencies fuel state) := by
  induction fuel generalizing state with
  | zero => exact covers
  | succ fuel ih => exact ih _ (advance_preserves_coverage dependencies roots state covers)

theorem completed_discovery_exact [DecidableEq Node]
    (dependencies : Node → List Node) (roots : List Node) (fuel : Nat)
    (complete : (discover dependencies fuel ⟨[], roots⟩).pending = []) (node : Node) :
    node ∈ (discover dependencies fuel ⟨[], roots⟩).seen ↔ Demanded dependencies roots node := by
  constructor
  · exact every_discovered_node_is_demanded dependencies roots fuel node
  · have initial : Covers dependencies roots (⟨[], roots⟩ : Discovery Node) := by
      constructor
      · exact fun root member => Or.inr member
      · simp
    have covers := discover_preserves_coverage dependencies roots fuel _ initial
    have finish : ∀ child, Scheduled (discover dependencies fuel ⟨[], roots⟩) child →
        child ∈ (discover dependencies fuel ⟨[], roots⟩).seen := by
      intro child scheduled
      rcases scheduled with present | pending
      · exact present
      · simp [complete] at pending
    intro demanded
    induction demanded with
    | root root member => exact finish root (covers.1 root member)
    | dependency parent child _ edge ih => exact finish child (covers.2 parent ih child edge)

theorem advance_preserves_unique_reads [DecidableEq Node]
    (dependencies : Node → List Node) (state : Discovery Node)
    (unique : state.seen.Nodup) : (advance dependencies state).seen.Nodup := by
  rcases state with ⟨seen, pending⟩
  cases pending with
  | nil => exact unique
  | cons node rest =>
    by_cases visited : node ∈ seen
    · simpa [advance, visited] using unique
    · simpa [advance, visited] using List.nodup_cons.mpr ⟨visited, unique⟩

theorem discover_preserves_unique_reads [DecidableEq Node]
    (dependencies : Node → List Node) (fuel : Nat) (state : Discovery Node)
    (unique : state.seen.Nodup) : (discover dependencies fuel state).seen.Nodup := by
  induction fuel generalizing state with
  | zero => exact unique
  | succ fuel ih => exact ih _ (advance_preserves_unique_reads dependencies state unique)

def SourcesCurrent (observed : List (Node × Revision)) (actual : Node → Revision) : Prop :=
  ∀ entry ∈ observed, actual entry.1 = entry.2

-- This bound is independent of catalog size and shared-edge multiplicity.
-- It counts discovery visits, NOT fresh source reads across effect boundaries.
-- Runtime import completeness and the Scheme hash-table cost remain premises.
theorem discovery_visit_bound [DecidableEq Node]
    (dependencies : Node → List Node) (catalog roots : List Node) (fuel : Nat)
    (rootCoverage : ∀ root ∈ roots, root ∈ catalog)
    (dependencyCoverage : ∀ node ∈ catalog, ∀ child ∈ dependencies node, child ∈ catalog) :
    (discover dependencies fuel ⟨[], roots⟩).seen.length ≤ catalog.length := by
  have initial : Inside (fun node => node ∈ catalog) (⟨[], roots⟩ : Discovery Node) :=
    ⟨by simp, rootCoverage⟩
  have covered := (discover_stays_inside dependencies (fun node => node ∈ catalog)
    dependencyCoverage fuel _ initial).1
  have unique := discover_preserves_unique_reads dependencies fuel
    (⟨[], roots⟩ : Discovery Node) (by simp)
  exact unique.length_le_of_subset covered

def SourceAdmitted (state : Discovery Node) (observed : List (Node × Revision))
    (actual : Node → Revision) : Prop :=
  state.pending = [] ∧
  (∀ node ∈ state.seen, ∃ revision, (node, revision) ∈ observed) ∧
  SourcesCurrent observed actual

-- Full configuration admission adds its own closure/policy proof. Test-source
-- evidence cannot stand in for it merely because the source epoch is shared.
def ConfigurationAdmitted (roots : List Node) (state : Discovery Node)
    (observed : List (Node × Revision)) (actual : Node → Revision)
    (configurationObligations : Prop) : Prop :=
  SourceAdmitted state observed actual ∧
  (∀ root ∈ roots, root ∈ state.seen) ∧ configurationObligations

theorem missing_selected_root_rejected (roots : List Node) (state : Discovery Node)
    (observed : List (Node × Revision)) (actual : Node → Revision)
    (configurationObligations : Prop) (root : Node) (selected : root ∈ roots)
    (missing : root ∉ state.seen) :
    ¬ ConfigurationAdmitted roots state observed actual configurationObligations := by
  intro admitted
  exact missing (admitted.2.1 root selected)

theorem failed_configuration_obligation_rejected (roots : List Node)
    (state : Discovery Node) (observed : List (Node × Revision))
    (actual : Node → Revision) (configurationObligations : Prop)
    (failed : ¬ configurationObligations) :
    ¬ ConfigurationAdmitted roots state observed actual configurationObligations := by
  intro admitted
  exact failed admitted.2.2

theorem changed_dependency_rejected (state : Discovery Node)
    (observed : List (Node × Revision)) (actual : Node → Revision)
    (entry : Node × Revision) (member : entry ∈ observed)
    (changed : actual entry.1 ≠ entry.2) :
    ¬ SourceAdmitted state observed actual := by
  intro admitted
  exact changed (admitted.2.2 entry member)

theorem missing_observation_rejected (state : Discovery Node)
    (observed : List (Node × Revision)) (actual : Node → Revision)
    (node : Node) (discovered : node ∈ state.seen)
    (missing : ∀ revision, (node, revision) ∉ observed) :
    ¬ SourceAdmitted state observed actual := by
  intro admitted
  obtain ⟨revision, member⟩ := admitted.2.1 node discovered
  exact missing revision member

theorem unfinished_discovery_rejected (state : Discovery Node)
    (observed : List (Node × Revision)) (actual : Node → Revision)
    (unfinished : state.pending ≠ []) : ¬ SourceAdmitted state observed actual := by
  intro admitted
  exact unfinished admitted.1

-- A shared dependency and a cycle are visited once, not recursively expanded
-- forever. Insufficient fuel retains pending work and cannot certify closure.
def sharedCycle : Nat → List Nat
  | 0 => [1, 2]
  | 1 => [3]
  | 2 => [3]
  | 3 => [0]
  | _ => []

theorem shared_cycle_completes :
    discover sharedCycle 8 ⟨[], [0]⟩ = ⟨[2, 3, 1, 0], []⟩ := by decide

def independentOwners : Nat → List Nat
  | 0 => [1]
  | 2 => [3]
  | _ => []

theorem test_demand_does_not_discover_other_selected_owner :
    discover independentOwners 4 ⟨[], [0]⟩ = ⟨[1, 0], []⟩ := by decide

theorem full_demand_uses_same_dependencies :
    discover independentOwners 8 ⟨[], [0, 2]⟩ = ⟨[3, 2, 1, 0], []⟩ := by decide

/-- The list records deterministic admission order. Only the native indexed
membership participates in the worklist decision. It is invocation-local. -/
structure IndexedDiscovery where
  ordered : Discovery Nat
  visited : Std.HashSet Nat

def IndexedDiscovery.Exact (state : IndexedDiscovery) : Prop :=
  ∀ node, node ∈ state.visited ↔ node ∈ state.ordered.seen

def advanceIndexed (dependencies : Nat → List Nat) (state : IndexedDiscovery) :
    IndexedDiscovery :=
  match state.ordered.pending with
  | [] => state
  | node :: rest =>
    if node ∈ state.visited then
      { state with ordered := ⟨state.ordered.seen, rest⟩ }
    else
      ⟨⟨node :: state.ordered.seen, dependencies node ++ rest⟩, state.visited.insert node⟩

/-- An already visited root or shared edge consumes its queue entry without
expanding its outgoing bucket again. -/
theorem advance_indexed_skips_visited (dependencies : Nat → List Nat)
    (seen pending : List Nat) (visited : Std.HashSet Nat) (owner : Nat)
    (present : owner ∈ visited) :
    advanceIndexed dependencies ⟨⟨seen, owner :: pending⟩, visited⟩ =
      ⟨⟨seen, pending⟩, visited⟩ := by
  simp [advanceIndexed, present]

theorem advance_indexed_refines (dependencies : Nat → List Nat)
    (state : IndexedDiscovery) (exactIndex : state.Exact) :
    (advanceIndexed dependencies state).ordered = advance dependencies state.ordered ∧
      (advanceIndexed dependencies state).Exact := by
  rcases state with ⟨⟨seen, pending⟩, visited⟩
  cases pending with
  | nil => exact ⟨rfl, exactIndex⟩
  | cons node rest =>
    have index : ∀ k, k ∈ visited ↔ k ∈ seen := exactIndex
    by_cases present : node ∈ visited
    · have inList := (index node).mp present
      exact ⟨by simp [advanceIndexed, advance, present, inList],
        by simpa [advanceIndexed, present, IndexedDiscovery.Exact] using index⟩
    · have absent : node ∉ seen := fun member => present ((index node).mpr member)
      constructor
      · simp [advanceIndexed, advance, present, absent]
      · intro k
        simp [advanceIndexed, present, Std.HashSet.mem_insert, index k]
        exact or_congr eq_comm Iff.rfl

def discoverIndexed (dependencies : Nat → List Nat) :
    Nat → IndexedDiscovery → IndexedDiscovery
  | 0, state => state
  | fuel + 1, state => discoverIndexed dependencies fuel (advanceIndexed dependencies state)

theorem discover_indexed_refines (dependencies : Nat → List Nat) (fuel : Nat)
    (state : IndexedDiscovery) (exactIndex : state.Exact) :
    (discoverIndexed dependencies fuel state).ordered = discover dependencies fuel state.ordered := by
  induction fuel generalizing state with
  | zero => rfl
  | succ fuel ih =>
    have next := advance_indexed_refines dependencies state exactIndex
    simp only [discoverIndexed, discover, ih _ next.2, next.1]

theorem discover_indexed_keeps_exact (dependencies : Nat → List Nat) (fuel : Nat)
    (state : IndexedDiscovery) (exactIndex : state.Exact) :
    (discoverIndexed dependencies fuel state).Exact := by
  induction fuel generalizing state with
  | zero => exact exactIndex
  | succ fuel ih =>
    exact ih _ (advance_indexed_refines dependencies state exactIndex).2

theorem completed_indexed_discovery_exact (dependencies : Nat → List Nat) (roots : List Nat)
    (fuel : Nat)
    (complete : (discoverIndexed dependencies fuel ⟨⟨[], roots⟩, ∅⟩).ordered.pending = [])
    (node : Nat) :
    node ∈ (discoverIndexed dependencies fuel ⟨⟨[], roots⟩, ∅⟩).ordered.seen ↔
      Demanded dependencies roots node := by
  have same := discover_indexed_refines dependencies fuel ⟨⟨[], roots⟩, ∅⟩
    (by intro k; simp)
  rw [same] at complete ⊢
  exact completed_discovery_exact dependencies roots fuel complete node

theorem indexed_discovery_visit_bound (dependencies : Nat → List Nat)
    (catalog roots : List Nat) (fuel : Nat)
    (rootCoverage : ∀ root ∈ roots, root ∈ catalog)
    (dependencyCoverage : ∀ node ∈ catalog, ∀ child ∈ dependencies node, child ∈ catalog) :
    let result := discoverIndexed dependencies fuel ⟨⟨[], roots⟩, ∅⟩
    result.ordered.seen.Nodup ∧ result.ordered.seen.length ≤ catalog.length := by
  dsimp
  rw [discover_indexed_refines dependencies fuel ⟨⟨[], roots⟩, ∅⟩ (by intro k; simp)]
  exact ⟨discover_preserves_unique_reads dependencies fuel _ (by simp),
    discovery_visit_bound dependencies catalog roots fuel rootCoverage dependencyCoverage⟩

/-- First admission authenticates the reached owners. Full certification is
the same check with the complete roster as roots. The catalog predicate is a
point lookup in the existing directory. A dangling dependency fails closed. -/
def admitIndexed (state : IndexedDiscovery) (known verify : Nat → Bool) : Bool :=
  state.ordered.pending.isEmpty &&
    state.ordered.seen.all (fun owner => known owner && verify owner)

theorem indexed_admission_boundary (dependencies : Nat → List Nat)
    (roots : List Nat) (fuel : Nat) (known verify : Nat → Bool)
    (complete : (discoverIndexed dependencies fuel ⟨⟨[], roots⟩, ∅⟩).ordered.pending = []) :
    admitIndexed (discoverIndexed dependencies fuel ⟨⟨[], roots⟩, ∅⟩) known verify = true ↔
      ∀ owner, Demanded dependencies roots owner → known owner = true ∧ verify owner = true := by
  simp only [admitIndexed, complete, List.isEmpty_nil, Bool.true_and, List.all_eq_true,
    Bool.and_eq_true]
  exact forall_congr' fun owner =>
    imp_congr (completed_indexed_discovery_exact dependencies roots fuel complete owner) Iff.rfl

theorem full_catalog_certification_exact (dependencies : Nat → List Nat)
    (catalog : List Nat) (fuel : Nat) (known verify : Nat → Bool)
    (directory : ∀ owner, known owner = true ↔ owner ∈ catalog)
    (closed : ∀ owner ∈ catalog, ∀ child ∈ dependencies owner, child ∈ catalog)
    (complete : (discoverIndexed dependencies fuel ⟨⟨[], catalog⟩, ∅⟩).ordered.pending = []) :
    admitIndexed (discoverIndexed dependencies fuel ⟨⟨[], catalog⟩, ∅⟩) known verify = true ↔
      ∀ owner ∈ catalog, verify owner = true := by
  rw [indexed_admission_boundary dependencies catalog fuel known verify complete]
  constructor
  · intro all owner member
    exact (all owner (.root owner member)).2
  · intro all owner demand
    have member : owner ∈ catalog := by
      induction demand with
      | root _ member => exact member
      | dependency parent child _ edge ih => exact closed parent ih child edge
    exact ⟨(directory owner).mpr member, all owner member⟩

theorem incomplete_admission_refuses (state : IndexedDiscovery)
    (known verify : Nat → Bool) (pending : state.ordered.pending ≠ []) :
    admitIndexed state known verify = false := by
  cases h : state.ordered.pending with
  | nil => contradiction
  | cons head tail => simp [admitIndexed, h]

theorem empty_discovery_index_exact (roots : List Nat) :
    (⟨⟨[], roots⟩, ∅⟩ : IndexedDiscovery).Exact := by
  intro owner
  simp

/-- An independent bad declaration is outside a selected demand, but remains
observable when certifying the complete roster. -/
theorem selected_admission_is_not_catalog_certification :
    let known := fun owner => owner < 4
    let verify := fun owner => owner != 3
    admitIndexed (discoverIndexed independentOwners 4 ⟨⟨[], [0]⟩, ∅⟩) known verify = true ∧
    admitIndexed (discoverIndexed independentOwners 8 ⟨⟨[], [0, 1, 2, 3]⟩, ∅⟩)
      known verify = false := by
  dsimp only [admitIndexed]
  rw [discover_indexed_refines _ _ _ (empty_discovery_index_exact [0]),
    discover_indexed_refines _ _ _ (empty_discovery_index_exact [0, 1, 2, 3])]
  decide

/-- Both fixtures have 10,000 possible owners. The sparse query has two
reachable owners. The dense chain has exactly 9,999 edges. These are checked
algorithmic workloads, not Gerbil latency or a hash worst-case bound. -/
def tenThousandIndexedScale : Bool :=
  let sparse := discoverIndexed (fun node => if node = 1 then [0] else []) 2
    ⟨⟨[], [1]⟩, ∅⟩
  let dense := discoverIndexed (fun node => if node = 0 then [] else [node - 1]) 10000
    ⟨⟨[], [9999]⟩, ∅⟩
  sparse.ordered.seen == [0, 1] && sparse.ordered.pending.isEmpty &&
    dense.ordered.seen == List.range 10000 && dense.ordered.pending.isEmpty

#eval if tenThousandIndexedScale then "INDEXED-ADMISSION-10000-OK" else "INDEXED-ADMISSION-10000-FAIL"
#guard tenThousandIndexedScale

end YuanxuProof.ModuleSystem.Graph.TestAdmission
