-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.StableOrderRepair
import YuanxuProof.ModuleSystem.Graph.IndexedWork

/-! Yuanxu integration witnesses for the upstream graph contracts. -/
namespace YuanxuProof.ModuleSystem.Graph.DependencyOrderRepair
open LeanPoo.Functional.DependencyOrderRepair

-- Order repair must not substitute its interval for value invalidation.
theorem outside_order_interval_still_affected :
    Loading.IncrementalRoles.Affected
      (fun consumer provider : Nat => consumer = 9999 ∧ provider = 1)
      (fun node => node = 1) 9999 ∧
    9999 ∉ ([1, 9998] : List Nat) := by
  constructor
  · exact .consumer ⟨rfl, rfl⟩ (.source rfl)
  · decide

-- Qualification oracle only: it enumerates all keys to verify the final
-- order, while the instrumented model walks and patch have only two owners.
private def scale : Bool :=
  let deps := fun node => if node = 9999 then [1] else if node = 9998 then [0] else []
  let reverse := fun node => if node = 1 then [9999] else if node = 0 then [9998] else []
  let prune := fun node => decide (1 ≤ node ∧ node ≤ 9998)
  let forward := IndexedWork.run (fun node => (deps node).filter prune) 2 (IndexedWork.start [9998])
  let backward := IndexedWork.run (fun node => (reverse node).filter prune) 2 (IndexedWork.start [1])
  match proposeRanks id forward.discovery.ordered.seen backward.discovery.ordered.seen with
  | none => false
  | some patch =>
    let changed := forward.discovery.ordered.seen ++ backward.discovery.ordered.seen
    let owners := LeanPoo.Functional.Requirements.KeyIndex.ofKeys changed
    let rank := applyRanks owners patch id
    let inspected := (forward.discovery.ordered.seen.map (fun node => (deps node).length)).sum +
      (backward.discovery.ordered.seen.map (fun node => (reverse node).length)).sum
    let finalOrder := (List.range 10000).all fun node =>
      (if node = 1 then [9998] else deps node).all fun provider => rank provider < rank node
    let retained := (List.range 10000).filter fun node => decide (node ∉ changed)
    forward.discovery.ordered.pending.isEmpty && backward.discovery.ordered.pending.isEmpty &&
      forward.buckets == 1 && backward.buckets == 1 &&
      forward.discovery.ordered.seen == [9998] && backward.discovery.ordered.seen == [1] &&
      inspected == 2 && patch.size == 2 && rank 9998 == 1 && rank 1 == 9998 &&
      finalOrder && retained.all (fun node => rank node == node) &&
      -- A complete reverse invalidation independently includes the outer consumer.
      (IndexedWork.run reverse 2 (IndexedWork.start [1])).discovery.ordered.seen == [9999, 1]

#eval if scale then "DEPENDENCY-ORDER-REPAIR-10000-OK" else "DEPENDENCY-ORDER-REPAIR-10000-FAIL"
#guard scale

#guard (proposeRanks id [1, 2] [2, 3]).isNone
#guard (proposeRanks (fun _ => 0) [1] [2]).isNone

end YuanxuProof.ModuleSystem.Graph.DependencyOrderRepair
