-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Prototype.Generator

import YuanxuProof.ProfileComposition.Revision

namespace YuanxuProof.ProfileComposition.Prototype

open LeanPoo.Prototype

/-- Profile refinements use the dependency's actual ordered prototype chain.
The head is the child; regrouping cannot reorder operands or change final self. -/
theorem profileHeadRefinesInheritedTail
    (head : Proto Self Profile Profile) (tail : List (Proto Self Profile Profile))
    (self : Self) (base : Profile) :
    composeAll (head :: tail) self base = head self (composeAll tail self base) := rfl

theorem profileRefinementsKeepFinalSelf
    (child : Proto Self Profile Profile) (parent : Proto Self Base Profile)
    (base : Base) :
    Generator.applyProto child (Generator.ofProto parent base) =
      Generator.ofProto (compose child parent) base :=
  Generator.applyProto_ofProto child parent base

-- Refinement order is observable; composition is not commutative.
/-- The inherited formula observes the final receiver, not a previously
materialized parent's receiver. Native thunks/cache/hygiene remain bridge facts. -/
theorem ancestor_uses_final_receiver (receiver : Nat) :
    composeAll [fun (_ : Nat) (prior : Nat) => prior + 2,
      fun self _ => self + 1] receiver 0 = receiver + 3 := by
  rfl

-- A captured parent result (10 + 1) cannot stand in for inherited computation
-- at receiver 20. Namespace ancestry does not supply either numeric value.
#guard composeAll [fun (_ : Nat) (prior : Nat) => prior + 2,
    fun self _ => self + 1] 20 0 == 23
#guard (10 + 1 + 2 : Nat) !=
  composeAll [fun (_ : Nat) (prior : Nat) => prior + 2, fun self _ => self + 1] 20 0

#guard composeAll [fun (_ : Unit) (value : Nat) => value + 1,
    fun _ value => value * 2] () 3 == 7
#guard composeAll [fun (_ : Unit) (value : Nat) => value * 2,
    fun _ value => value + 1] () 3 == 8


end YuanxuProof.ProfileComposition.Prototype
