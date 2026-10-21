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
#guard composeAll [fun (_ : Unit) (value : Nat) => value + 1,
    fun _ value => value * 2] () 3 == 7
#guard composeAll [fun (_ : Unit) (value : Nat) => value * 2,
    fun _ value => value + 1] () 3 == 8


end YuanxuProof.ProfileComposition.Prototype
