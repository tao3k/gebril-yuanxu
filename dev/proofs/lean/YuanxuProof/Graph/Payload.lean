-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Prototype.Compose
import YuanxuProof.Graph.Operations

namespace YuanxuProof.Graph.Payload
open LeanPoo.Prototype

/-! List-valued, stable-distinct payload operations from `graph/payload-operations.ss` and
`operation.ss`: absent slots read as empty lists, untouched slots are retained.
These are pure prototypes, not a second Graph node or traversal implementation. -/
abbrev Payload := String → Option (List Nat)

def appendDistinct (base extra : List Nat) : List Nat :=
  extra.foldl (fun current value => if value ∈ current then current else current ++ [value]) base

def overrideSlot (key : String) (value : List Nat) : Proto Unit Payload Payload :=
  fun _ inherited query => if query = key then some value else inherited query

def appendSlot (key : String) (value : List Nat) : Proto Unit Payload Payload :=
  fun _ inherited query => if query = key then some (appendDistinct ((inherited key).getD []) value) else inherited query

def prependSlot (key : String) (value : List Nat) : Proto Unit Payload Payload :=
  fun _ inherited query => if query = key then some (appendDistinct value ((inherited key).getD [])) else inherited query

def removeSlot (key : String) (values : List Nat) : Proto Unit Payload Payload :=
  fun _ inherited query => if query = key then some (((inherited key).getD []).filter (fun value => !values.contains value)) else inherited query

/-- The native coalescer can fuse adjacent appends of ONE slot in encounter
order. No commutativity or cross-operation reordering is required. -/
theorem adjacent_appends_coalesce (key : String) (left right : List Nat) (payload : Payload) :
    appendSlot key right () (appendSlot key left () payload) = appendSlot key (left ++ right) () payload := by
  funext query
  by_cases same : query = key <;> simp [appendSlot, same, appendDistinct, List.foldl_append]

theorem append_other_slot_unchanged (key other : String) (values : List Nat) (payload : Payload)
    (different : other ≠ key) : appendSlot key values () payload other = payload other := by
  simp [appendSlot, different]

theorem override_then_append (key : String) (first rest : List Nat) (payload : Payload) :
    appendSlot key rest () (overrideSlot key first () payload) key = some (appendDistinct first rest) := by
  simp [appendSlot, overrideSlot]

#guard appendSlot "x" [2] () (appendSlot "x" [1] () (fun _ => none)) "x" == some [1, 2]
#guard prependSlot "x" [2] () (appendSlot "x" [1] () (fun _ => none)) "x" == some [2, 1]
#guard removeSlot "x" [1] () (appendSlot "x" [1] () (fun _ => none)) "x" == some []
end YuanxuProof.Graph.Payload
