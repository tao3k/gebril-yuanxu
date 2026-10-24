-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly
import YuanxuProof.ProfileComposition.BundleIdentity
import YuanxuProof.ProfileComposition.Prototype

namespace YuanxuProof.ProfileComposition.Composition
open LeanPoo.Functional
open BundleIdentity

/-! `profile-bundle.ss:yuanxu-compose-profile-bundles`: flatten operands in
order; first occurrence wins, incompatible repeated selections abort the whole
composition. Stage refinements use the dependency's actual open-self prototypes. -/
def collect : List Binding → List Binding → Except Conflict (List Binding)
  | accumulated, [] => .ok accumulated
  | accumulated, head :: rest => (insert accumulated head).bind (fun next => collect next rest)

def composeBindings (operands : List (List Binding)) := collect [] operands.flatten

theorem collect_append (initial left right : List Binding) :
    collect initial (left ++ right) = (collect initial left).bind (fun next => collect next right) := by
  induction left generalizing initial with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.cons_append, collect]
    cases insert initial head <;> simp [Except.bind, ih]

/-- Grouping nested operands cannot change conflict selection or final order. -/
theorem operand_grouping (left right : List (List Binding)) :
    composeBindings (left ++ right) =
      (composeBindings left).bind (fun next => collect next right.flatten) := by
  simp only [composeBindings, List.flatten_append, collect_append]

theorem conflicting_prefix_aborts (initial earlier later : List Binding) (failure : Conflict)
    (rejected : collect initial earlier = .error failure) :
    collect initial (earlier ++ later) = .error failure := by
  rw [collect_append, rejected]; rfl

theorem insert_retains_existing (initial : List Binding) (candidate : Binding) (output : List Binding)
    (accepted : insert initial candidate = .ok output) : ∃ extra, output = initial ++ extra := by
  unfold BundleIdentity.insert at accepted
  split at accepted
  · exact ⟨[candidate], (Except.ok.inj accepted).symm⟩
  · split at accepted
    · exact ⟨[], by simpa using (Except.ok.inj accepted).symm⟩
    · contradiction

theorem composition_retains_existing (initial added output : List Binding)
    (accepted : collect initial added = .ok output) : ∃ extra, output = initial ++ extra := by
  induction added generalizing initial with
  | nil => exact ⟨[], by simpa [collect] using accepted.symm⟩
  | cons head tail ih =>
    cases inserted : insert initial head with
    | error failure => simp [collect, inserted, Except.bind] at accepted
    | ok next =>
      have continued : collect next tail = .ok output := by
        simpa [collect, inserted, Except.bind] using accepted
      obtain ⟨first, rfl⟩ := insert_retains_existing initial head next inserted
      obtain ⟨rest, same⟩ := ih (initial ++ first) continued
      exact ⟨first ++ rest, by simpa [List.append_assoc] using same⟩

def stableUnion [DecidableEq Value] (operands : List (List Value)) : List Value :=
  operands.flatten.eraseDups

theorem union_membership [DecidableEq Value] (operands : List (List Value)) (value : Value) :
    value ∈ stableUnion operands ↔ ∃ operand ∈ operands, value ∈ operand := by
  simp [stableUnion]

/-- The final self is supplied once to every retained refinement. No local
prototype engine, scheduler or fixed-point iteration is introduced. -/
def stages (prototypes : List (LeanPoo.Prototype.Proto Self Stage Stage)) (base : Stage) :
    Factory Self (fun _ => Stage) :=
  fun self => LeanPoo.Prototype.composeAll prototypes self base

theorem stage_final_self (head : LeanPoo.Prototype.Proto Self Stage Stage)
    (tail : List (LeanPoo.Prototype.Proto Self Stage Stage)) (base : Stage) (self : Self) :
    stages (head :: tail) base self = head self (stages tail base self) := rfl

#guard (composeBindings [[.direct "a" 1, .direct "b" 2], [.direct "a" 1]]).toOption ==
  some [.direct "a" 1, .direct "b" 2]
#guard match composeBindings [[.direct "a" 1], [.direct "a" 9], [.direct "b" 2]] with
  | .error .distinctDirectValues => true | _ => false
#guard stableUnion [["x", "y"], ["x", "z"]] == ["x", "y", "z"]
#guard stages [fun (self : Nat) inherited => self + inherited, fun _ inherited => inherited * 2] 3 4 == 10
end YuanxuProof.ProfileComposition.Composition
