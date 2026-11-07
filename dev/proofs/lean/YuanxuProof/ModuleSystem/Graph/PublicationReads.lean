-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission

namespace YuanxuProof.ModuleSystem.Graph.PublicationReads
open TestAdmission

-- Identity normalization preserves the full original suffix. No assumption
-- about callback purity, Contract identity labels or token payload equality.
theorem same_roots_same_demands (deps : α → List α) (left right : List α)
    (same : ∀ node, node ∈ left ↔ node ∈ right) (node : α) :
    Demanded deps left node ↔ Demanded deps right node := by
  constructor
  · intro demand
    induction demand with
    | root node member => exact Demanded.root node ((same node).mp member)
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge
  · intro demand
    induction demand with
    | root node member => exact Demanded.root node ((same node).mpr member)
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge

theorem dedup_preserves_demands [BEq α] [LawfulBEq α]
    (deps : α → List α) (roots : List α) (node : α) :
    Demanded deps roots node ↔ Demanded deps roots.eraseDups node := by
  apply same_roots_same_demands
  intro node
  simp

def Current (deps : α → List α) (roots : List α) (fresh : α → Prop) : Prop :=
  ∀ node, Demanded deps roots node → fresh node

theorem dedup_preserves_currentness [BEq α] [LawfulBEq α]
    (deps : α → List α) (roots : List α) (fresh : α → Prop) :
    Current deps roots fresh ↔ Current deps roots.eraseDups fresh := by
  constructor
  · intro current node demanded
    exact current node ((dedup_preserves_demands deps roots node).mpr demanded)
  · intro current node demanded
    exact current node ((dedup_preserves_demands deps roots node).mp demanded)

-- Runtime correspondence premises remain: eq?-identity normalization,
-- unmodified original dependency lists, public replay's final recheck,
-- unchanged real observer delivery, and no nonlocal continuation escape.
-- This does not prove SDK ownership, GC behavior or a memory byte bound.
-- Each result carries its own ordered read delivery. Fixed support can be
-- authenticated once for a closed run of these independently evaluated rows.
def checkStockEach {Failure Result : Type} (check : Except Failure Unit) :
    List (Except Failure Result) → Except Failure (List Result)
  | [] => .ok []
  | result :: rest => do
      check
      let value ← result
      let values ← checkStockEach check rest
      pure (value :: values)

def checkStockRun {Failure Result : Type} (check : Except Failure Unit)
    (stock : List (Except Failure Result)) : Except Failure (List Result) :=
  match stock with
  | [] => .ok []
  | _ :: _ => do
      check
      checkStockEach (.ok ()) stock

theorem unchanged_stock_support_preserves_results_and_refusal
    (check : Except Failure Unit) (stock : List (Except Failure Result)) :
    checkStockRun check stock = checkStockEach check stock := by
  cases check <;> cases stock <;> rfl

-- The author call owns two fresh guards. The next closed run consumes the
-- post-effect state, even if the previous run had valid support.
def stockAroundOpen {World Failure Result : Type}
    (run : Except Failure Unit → List (Except Failure Result) → Except Failure (List Result))
    (check : World → Except Failure Unit) (author : World → World)
    (left right : World → List (Except Failure Result)) (start : World) :
    Except Failure (List Result × List Result × World) := do
  let first ← run (check start) (left start)
  check start
  let current := author start
  check current
  let last ← run (check current) (right current)
  pure (first, last, current)

theorem stock_runs_preserve_independent_open_checks
    (check : World → Except Failure Unit) (author : World → World)
    (left right : World → List (Except Failure Result)) (start : World) :
    stockAroundOpen checkStockRun check author left right start =
      stockAroundOpen checkStockEach check author left right start := by
  simp only [stockAroundOpen, unchanged_stock_support_preserves_results_and_refusal]

example : stockAroundOpen (Result := Nat) checkStockRun
    (fun changed => if changed then .error "stale method" else .ok ())
    (fun _ => true) (fun _ => List.replicate 9 (.ok 1)) (fun _ => []) false =
      .error "stale method" := rfl
end YuanxuProof.ModuleSystem.Graph.PublicationReads
