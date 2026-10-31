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

-- Native correspondence premises remain: eq?-identity normalization,
-- unmodified original dependency lists, public replay's final recheck,
-- unchanged real observer delivery, and no nonlocal continuation escape.
-- This does not prove SDK ownership, GC behavior or a memory byte bound.
end YuanxuProof.ModuleSystem.Graph.PublicationReads
