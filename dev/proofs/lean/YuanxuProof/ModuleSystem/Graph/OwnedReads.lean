-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.SemanticReads
import YuanxuProof.ModuleSystem.Graph.TestAdmission

namespace YuanxuProof.ModuleSystem.Graph.OwnedReads
open SemanticReads
open TestAdmission

def witnessReplayQuintDigest : String :=
  "sha256:9b38bec4e849474ecb69a2ca83dfe1e8befaced440347de0cc65e2dc5b3032d1"

-- The native batch pins live receivers and resolves their original tokens
-- BEFORE replay. This equivalence is at one stable query epoch; arbitrary
-- effectful validators are not proved interchangeable by this law.
def WitnessGroupsCurrent (groups : List (List α)) (current : α → Prop) : Prop :=
  ∀ group, group ∈ groups → ∀ token, token ∈ group → current token

theorem live_witness_batch_exact_support (groups : List (List α))
    (current : α → Prop) :
    WitnessGroupsCurrent groups current ↔
      ∀ token, token ∈ groups.flatten → current token := by
  constructor
  · intro each token member
    rcases List.mem_flatten.mp member with ⟨group, covered, present⟩
    exact each group covered token present
  · intro batch group covered token present
    exact batch token (List.mem_flatten.mpr ⟨group, covered, present⟩)

theorem final_witness_mutation_refused (groups : List (List α))
    (current : α → Prop) (token : α)
    (covered : token ∈ groups.flatten) (stale : ¬ current token) :
    ¬ WitnessGroupsCurrent groups current := by
  intro accepted
  exact stale ((live_witness_batch_exact_support groups current).mp accepted token covered)

-- n + 1 live receivers with the same suffix. Native DFS identity uniqueness
-- gives the batched bound; this arithmetic does not prove SDK/GC behavior.
theorem shared_witness_suffix_work (n own shared : Nat) :
    (n + 1) * (own + shared) =
      (n + 1) * own + shared + n * shared := by
  simp only [Nat.mul_add, Nat.add_mul, Nat.one_mul]
  omega

-- Factory enrollment and the first native generation are runtime premises,
-- not a certificate inferred from a receiver's kind or prototype label.
def ClosureCertified (known constructor unchanged : Prop) : Prop :=
  known ∧ constructor ∧ unchanged

theorem borrowed_copy_not_certified {known constructor unchanged : Prop}
    (borrowed : ¬ constructor) : ¬ ClosureCertified known constructor unchanged := by
  intro certified
  exact borrowed certified.2.1

theorem edited_generation_not_certified {known constructor unchanged : Prop}
    (edited : ¬ unchanged) : ¬ ClosureCertified known constructor unchanged := by
  intro certified
  exact edited certified.2.2

-- The Core adapter owns the fresh receiver supplied by native rebind-validation,
-- not its borrowed ancestors. Their FIRST native revisions stay strong policy
-- support even when the temporary receiver has been collected.
def ParentSnapshotCurrent (parents : List α) (before now : α → Nat) : Prop :=
  ∀ parent, parent ∈ parents → before parent = now parent

theorem changed_parent_refused {parents : List α} {before now : α → Nat}
    {parent : α} (covered : parent ∈ parents) (changed : before parent ≠ now parent) :
    ¬ ParentSnapshotCurrent parents before now := by
  intro current
  exact changed (current parent covered)

theorem ancestor_policy_preserved {parents roots : List α} {supers : α → List α}
    {before now : α → Nat}
    (coverage : ∀ parent, Demanded supers roots parent → parent ∈ parents)
    (current : ParentSnapshotCurrent parents before now) :
    ∀ parent, Demanded supers roots parent → before parent = now parent := by
  intro parent demanded
  exact current parent (coverage parent demanded)

-- The Scheme DFS marks identity before recursion and only descends through
-- owned tokens. Reuse the existing worklist discovery proof for that cut graph.
def ownedDependencies (owned : α → Prop) [DecidablePred owned]
    (deps : α → List α) (node : α) : List α :=
  if owned node then deps node else []

theorem demanded_is_cut_or_below_frontier
    (owned : α → Prop) [DecidablePred owned] (deps : α → List α)
    (roots : List α) {node : α} (demand : Demanded deps roots node) :
    Demanded (ownedDependencies owned deps) roots node ∨
      ∃ frontier, Demanded (ownedDependencies owned deps) roots frontier ∧
        ¬ owned frontier ∧ Demanded deps [frontier] node := by
  induction demand with
  | root node member => exact Or.inl (Demanded.root node member)
  | dependency parent child _ edge ih =>
    rcases ih with cut | below
    · by_cases isOwned : owned parent
      · exact Or.inl (Demanded.dependency parent child cut (by
          simpa [ownedDependencies, isOwned] using edge))
      · exact Or.inr ⟨parent, cut, isOwned,
          Demanded.dependency parent child (Demanded.root parent (by simp)) edge⟩
    · obtain ⟨frontier, cut, ext, path⟩ := below
      exact Or.inr ⟨frontier, cut, ext, Demanded.dependency parent child path edge⟩

theorem completed_frontier_covers_external [DecidableEq α]
    (owned : α → Prop) [DecidablePred owned] (deps : α → List α)
    (roots : List α) (fuel : Nat)
    (complete : (discover (ownedDependencies owned deps) fuel ⟨[], roots⟩).pending = [])
    {node : α} (demand : Demanded deps roots node) (external : ¬ owned node) :
    ∃ frontier,
      frontier ∈ (discover (ownedDependencies owned deps) fuel ⟨[], roots⟩).seen ∧
      ¬ owned frontier ∧ Demanded deps [frontier] node := by
  rcases demanded_is_cut_or_below_frontier owned deps roots demand with cut | below
  · exact ⟨node,
      (completed_discovery_exact (ownedDependencies owned deps) roots fuel complete node).mpr cut,
      external, Demanded.root node (by simp)⟩
  · obtain ⟨frontier, cut, ext, path⟩ := below
    exact ⟨frontier,
      (completed_discovery_exact (ownedDependencies owned deps) roots fuel complete frontier).mpr cut,
      ext, path⟩

-- GC/identity premise: a still-reachable semantic carrier remains weakly alive.
-- These are hypotheses about the native weak-value table, not a Lean GC model.
def Admitted (externalCurrent policyCurrent alive token originalCurrent : Prop) : Prop :=
  externalCurrent ∧ policyCurrent ∧ (¬ alive ∨ (token ∧ originalCurrent))

theorem external_change_refused {e p a t o : Prop} (changed : ¬ e) :
    ¬ Admitted e p a t o := fun accepted => changed accepted.1

theorem missing_live_token_refused {e p a t o : Prop}
    (live : a) (missing : ¬ t) : ¬ Admitted e p a t o := by
  intro accepted
  rcases accepted.2.2 with dead | original
  · exact dead live
  · exact missing original.1

theorem live_carrier_uses_original_replay {e p a t o : Prop}
    (accepted : Admitted e p a t o) (live : a) : o := by
  rcases accepted.2.2 with dead | original
  · exact False.elim (dead live)
  · exact original.2

theorem collected_carrier_does_not_waive_external
    {e p a t o : Prop} (accepted : Admitted e p a t o) : e ∧ p :=
  ⟨accepted.1, accepted.2.1⟩

theorem projection_sound {external required fresh : α → Prop}
    {policy alive token original : Prop}
    (coverage : ∀ n, required n → external n ∨ (alive ∧ (original → fresh n)))
    (accepted : Admitted (Current external fresh) policy alive token original) :
    Current required fresh := by
  intro node needed
  rcases coverage node needed with ext | carrier
  · exact accepted.1 node ext
  · exact carrier.2 (live_carrier_uses_original_replay accepted carrier.1)

end YuanxuProof.ModuleSystem.Graph.OwnedReads
