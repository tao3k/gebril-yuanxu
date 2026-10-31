-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Semantics

/-! Success semantics of the Scheme recursive DFS: visiting/done states, ordered
parent calls and done-cache skips. Fuel exhaustion and cycles refuse. Native
object/eq? projection is handled separately; no Scheme evaluator is axiomatized. -/
namespace YuanxuProof.ModuleSystem.Schema.Association.Traversal

inductive Error where
  | exhausted | cycle (node : Nat)
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Repr

def Closed (parents : Parents) (done : List Nat) : Prop :=
  ∀ node ∈ done, ∀ parent ∈ parents node, parent ∈ done

def visitParents (step : Nat → List Nat → Except Error (List Nat)) :
    List Nat → List Nat → Except Error (List Nat)
  | [], done => .ok done
  | parent :: rest, done => do
      let next ← step parent done
      visitParents step rest next

def visit (parents : Parents) : Nat → Nat → List Nat → List Nat → Except Error (List Nat)
  | 0, _, _, _ => .error .exhausted
  | fuel + 1, node, active, done =>
      if node ∈ active then .error (.cycle node)
      else if node ∈ done then .ok done
      else do
        let next ← visitParents
          (fun parent prior => visit parents fuel parent (node :: active) prior)
          (parents node) done
        pure (node :: next)

/-- Generic parent-loop invariant. New nodes are inherited from root, old nodes
are retained, every requested parent becomes done, and done remains closed. -/
theorem visitParents_spec (parents : Parents) (root : Nat)
    (step : Nat → List Nat → Except Error (List Nat)) (nodes initial final : List Nat)
    (closed : Closed parents initial)
    (stepSpec : ∀ parent ∈ nodes, ∀ prior next, Closed parents prior →
      step parent prior = .ok next →
      prior ⊆ next ∧ parent ∈ next ∧ Closed parents next ∧
        (∀ node ∈ next, node ∈ prior ∨ Inherits parents root node))
    (success : visitParents step nodes initial = .ok final) :
    initial ⊆ final ∧ (∀ parent ∈ nodes, parent ∈ final) ∧ Closed parents final ∧
      (∀ node ∈ final, node ∈ initial ∨ Inherits parents root node) := by
  induction nodes generalizing initial final with
  | nil =>
      simp only [visitParents] at success
      cases success
      exact ⟨fun _ h => h, by simp, closed, fun _ h => Or.inl h⟩
  | cons parent rest ih =>
      cases result : step parent initial with
      | error err => simp [visitParents, result, bind, Except.bind] at success
      | ok middle =>
          have first := stepSpec parent (by simp) initial middle closed result
          have remaining : visitParents step rest middle = .ok final := by
            simpa [visitParents, result, bind, Except.bind] using success
          have next := ih middle final first.2.2.1
            (fun node member prior after valid ok =>
              stepSpec node (by simp [member]) prior after valid ok) remaining
          refine ⟨fun node member => next.1 (first.1 member), ?_, next.2.2.1, ?_⟩
          · intro node member
            rcases List.mem_cons.mp member with same | tail
            · subst node; exact next.1 first.2.1
            · exact next.2.1 node tail
          · intro node member
            rcases next.2.2.2 node member with old | inherited
            · exact first.2.2.2 node old
            · exact Or.inr inherited

theorem visit_spec (parents : Parents) (fuel node : Nat) (active initial final : List Nat)
    (closed : Closed parents initial)
    (success : visit parents fuel node active initial = .ok final) :
    initial ⊆ final ∧ node ∈ final ∧ Closed parents final ∧
      (∀ root ∈ final, root ∈ initial ∨ Inherits parents node root) := by
  induction fuel generalizing node active initial final with
  | zero => simp [visit] at success
  | succ fuel ih =>
      unfold visit at success
      split at success
      · simp at success
      · split at success
        · cases success
          rename_i done
          exact ⟨fun _ h => h, done, closed, fun _ h => Or.inl h⟩
        · cases result : visitParents
              (fun parent prior => visit parents fuel parent (node :: active) prior)
              (parents node) initial with
          | error err => simp [result, bind, Except.bind] at success
          | ok middle =>
              have loop := visitParents_spec parents node
                (fun parent prior => visit parents fuel parent (node :: active) prior)
                (parents node) initial middle closed (by
                  intro parent member prior after valid ok
                  have spec := ih parent (node :: active) prior after valid ok
                  exact ⟨spec.1, spec.2.1, spec.2.2.1, fun root found => by
                    rcases spec.2.2.2 root found with old | path
                    · exact Or.inl old
                    · exact Or.inr (.step member path)⟩) result
              simp [result, bind, Except.bind, pure, Except.pure] at success
              cases success
              refine ⟨fun _ h => List.mem_cons_of_mem _ (loop.1 h), by simp, ?_, ?_⟩
              · intro current member parent edge
                rcases List.mem_cons.mp member with same | old
                · subst current; exact List.mem_cons_of_mem _ (loop.2.1 parent edge)
                · exact List.mem_cons_of_mem _ (loop.2.2.1 current old parent edge)
              · intro root member
                rcases List.mem_cons.mp member with same | old
                · subst root; exact Or.inr (.self node)
                · exact loop.2.2.2 root old

theorem closed_inherits (parents : Parents) (done : List Nat) (closed : Closed parents done)
    {node root : Nat} (present : node ∈ done) (path : Inherits parents node root) :
    root ∈ done := by
  induction path with
  | self => exact present
  | step edge path ih => exact ih (closed _ present _ edge)

/-- On normal completion from an empty cache, DFS done-membership is exactly
native reflexive parent reachability. No termination/fuel bound is assumed proved. -/
theorem success_membership_iff (parents : Parents) (fuel node : Nat) (final : List Nat)
    (success : visit parents fuel node [] [] = .ok final) (root : Nat) :
    root ∈ final ↔ Inherits parents node root := by
  have spec := visit_spec parents fuel node [] [] final (by simp [Closed]) success
  constructor
  · intro found
    rcases spec.2.2.2 root found with absent | path
    · simp at absent
    · exact path
  · exact closed_inherits parents final spec.2.2.1 spec.2.1

def dfsAssociations (done : List Nat) (index : List Anchor) : List Anchor :=
  index.filter (fun anchor => decide (anchor.root ∈ done))

theorem successful_dfs_association_iff (parents : Parents) (fuel node : Nat)
    (final : List Nat) (index : List Anchor) (anchor : Anchor)
    (success : visit parents fuel node [] [] = .ok final) :
    anchor ∈ dfsAssociations final index ↔
      anchor ∈ index ∧ Inherits parents node anchor.root := by
  simp only [dfsAssociations, List.mem_filter, decide_eq_true_eq]
  rw [success_membership_iff parents fuel node final success]

#print axioms visit_spec
#print axioms success_membership_iff
#print axioms successful_dfs_association_iff
end YuanxuProof.ModuleSystem.Schema.Association.Traversal
