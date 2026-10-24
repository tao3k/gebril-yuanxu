-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-! Pure laws for the ordered Graph operation boundary. These laws do not prove
Scheme refinement or resource bounds. The finite Quint program and native tests
remain independent evidence. LeanPoo owns native POO composition separately. -/
namespace YuanxuProof.Graph.Operations

def quintSourceDigest : String := "sha256:4cef3a2a0e39d308b5af97b48767f68b058e04a4bb418bdb33890318bc431a2a"
def quintInvariantNames : List String :=
  ["OrderedPayload", "PathIdentity", "StructuralClosure", "InsertThenTarget", "HonestReceipt"]

def applyOperations (initial : State) (operations : List (State → State)) : State :=
  operations.foldl (fun state operation => operation state) initial

@[simp] theorem empty_operations (initial : State) :
    applyOperations initial [] = initial := rfl

theorem contribution_order (initial : State) (before after : List (State → State)) :
    applyOperations initial (before ++ after) =
      applyOperations (applyOperations initial before) after := by
  simp [applyOperations, List.foldl_append]

structure ApplicationReceipt where
  changedPasses : Nat
  applied : Bool
  deriving DecidableEq, Repr

def receipt [DecidableEq State] (before after : State) : ApplicationReceipt :=
  { changedPasses := if before = after then 0 else 1, applied := true }

theorem completed_receipt [DecidableEq State] (before after : State) :
    (receipt before after).applied = true := rfl

theorem at_most_one_changed_pass [DecidableEq State] (before after : State) :
    (receipt before after).changedPasses ≤ 1 := by
  unfold receipt
  split <;> simp

def retainEdges (live : Node → Bool) (edges : List (Node × Node)) : List (Node × Node) :=
  edges.filter (fun edge => live edge.1 && live edge.2)

theorem retained_endpoints_live (live : Node → Bool) (edges : List (Node × Node))
    (edge : Node × Node) (h : edge ∈ retainEdges live edges) :
    live edge.1 = true ∧ live edge.2 = true := by
  have selected := (List.mem_filter.mp h).2
  simpa only [Bool.and_eq_true] using selected

theorem distinct_containment_paths :
    ([0, 1, 3] : List Nat) ≠ [0, 2, 3] := by decide

structure ExampleState where
  childPresent : Bool
  marked : Bool
  deriving DecidableEq, Repr

def markIfPresent (state : ExampleState) : ExampleState :=
  if state.childPresent then { state with marked := true } else state

def insertChild (state : ExampleState) : ExampleState :=
  { state with childPresent := true }

def initial : ExampleState := ⟨false, false⟩
def pending : List (ExampleState → ExampleState) := [markIfPresent, insertChild]

theorem first_pass_inserts_unmarked :
    applyOperations initial pending = ⟨true, false⟩ := rfl

theorem completed_pass_is_not_a_fixed_point :
    applyOperations (applyOperations initial pending) pending ≠
      applyOperations initial pending := by decide

end YuanxuProof.Graph.Operations
