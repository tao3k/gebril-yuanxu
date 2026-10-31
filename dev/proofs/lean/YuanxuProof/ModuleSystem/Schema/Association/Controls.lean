-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Semantics

/-! Finite controls aligned with the native probe. Numbers are identity tokens,
not language names, task counts imposed on users, or source-authentication IDs. -/
namespace YuanxuProof.ModuleSystem.Schema.Association.Controls
open LeanPoo.Functional.Requirements

def graph : Parents
  | 1 => [0]
  | 3 => [1, 2]
  | 5 => plusParents 0 []
  | 7 => [1, 8]
  | 8 => [0]
  | _ => []

def left : Anchor := ⟨0, 10, 1, 1⟩
def other : Anchor := ⟨2, 20, 1, 1⟩
def right : Anchor := ⟨4, 40, 1, 1⟩
def sameObjectOtherContract : Anchor := ⟨0, 11, 1, 1⟩
def roots := [left, other, right]

#guard associations graph 2 1 roots == [left]
#guard associations graph 3 3 roots == [left, other]
#guard associations graph 3 7 roots == [left]
#guard associations graph 2 5 roots == [left]
#guard !((associations graph 2 5 roots).contains right)
#guard associations graph 2 1 [left, sameObjectOtherContract] == [left, sameObjectOtherContract]
#guard plusParents 0 [2] == [2, 0]
#guard !((plusParents 0 []).contains 4)
#guard (match requirementGate [10, 40] [10] with
  | .error missing => missing == [10, 40] | .ok _ => false)
#guard (match requirementGate [10, 40] [10, 40] with
  | .ok _ => true | .error _ => false)

#guard (match compositionGate [10, 40] [10] (fun _ => true) with
  | .error missing => missing == [10, 40] | .ok _ => false)
#guard (match compositionGate [10, 40] [10, 40] (fun _ => true) with
  | .ok _ => true | .error _ => false)
#guard (match compositionGate [10, 40] [10, 40] (fun id => id != 40) with
  | .error failed => failed == [10, 40] | .ok _ => false)

def parent : View := ⟨1, 1, 1, 1, 1⟩
def child : View := ⟨2, 2, 1, 1, 1⟩
def smoke : View := ⟨3, 3, 1, 1, 1⟩
def effective (view : View) : CheckIDs :=
  if view.receiver = 1 then [100, 101, 102]
  else if view.receiver = 2 then [200, 101, 102]
  else [200, 101, 102, 203]

def warmed : PipelineCache effective :=
  ((ContextSlot.empty (finalFamily effective)).read parent).2.1

#guard (warmed.read parent).2.2
#guard !(warmed.read child).2.2
#guard cachedChecks effective warmed child == [200, 101, 102]
#guard cachedChecks effective warmed smoke == [200, 101, 102, 203]
#guard finalValueGate effective child (cachedChecks effective warmed child)
#guard !(finalValueGate effective child (effective parent))
#guard (effective parent).length == (effective child).length
#guard cachedChecks effective warmed parent == [100, 101, 102]

-- Distinct receiver IDs forbid transporting the parent's context proof.
example : parent ≠ child := by decide
example : effective parent ≠ effective child := by decide
example : finalValueGate effective child (effective parent) = false :=
  stale_parent_value_refused effective parent child (by decide)
example : right ∉ associations graph 2 5 roots := by decide
example : requirementGate [10, 40] [10] = .error [10, 40] :=
  missing_right_requirement_refused [10, 40] [10] 40 (by decide) (by decide)

end YuanxuProof.ModuleSystem.Schema.Association.Controls
