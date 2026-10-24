-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.Cache

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

inductive Demanded (dependencies : Node → List Node) (roots : List Node) : Node → Prop
  | root (node : Node) : node ∈ roots → Demanded dependencies roots node
  | dependency (parent child : Node) : Demanded dependencies roots parent →
      child ∈ dependencies parent → Demanded dependencies roots child

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

end YuanxuProof.ModuleSystem.Graph.TestAdmission
