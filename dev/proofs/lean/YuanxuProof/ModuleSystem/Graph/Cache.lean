-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.ContextSlot


namespace YuanxuProof.ModuleSystem.Graph.Cache


open LeanPoo.Functional.Requirements

/-- The current graph-closure proposition is certified together with the result
at every exact context. A cache entry no longer carries an unrelated freshness flag. -/
theorem cacheReadEstablishesCurrentGraphClosure
    {Context Key : Type} [DecidableEq Context] {Value : Context → Key → Type}
    {keys : List Key} {GraphClosure : Context → Prop}
    {ResultContract : ∀ c, Results Value c keys → Prop}
    (ready : Certified keys (fun c data => GraphClosure c ∧ ResultContract c data))
    (slot : ContextSlot ready) (context : Context) :
    GraphClosure context ∧ ResultContract context (slot.read context).1.val :=
  (slot.read context).1.property.2

/-- Changed semantic cuts cannot report a hit. Equality belongs to the complete
context, not an assumed injective digest or a separately asserted cache key. -/
theorem changedCutCannotHit
    {Context Key : Type} [DecidableEq Context] {Value : Context → Key → Type}
    {keys : List Key} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (before after : Context) (different : before ≠ after)
    (data : Snapshot ready before) :
    (({retained := some ⟨before, data⟩} : ContextSlot ready).read after).2.2 = false := by
  exact (ContextSlot.read_miss _ after (by
    intro previous retained saved
    have same : before = previous := by
      have equal := Option.some.inj saved
      exact congrArg Sigma.fst equal
    exact same ▸ different)).1


end YuanxuProof.ModuleSystem.Graph.Cache
