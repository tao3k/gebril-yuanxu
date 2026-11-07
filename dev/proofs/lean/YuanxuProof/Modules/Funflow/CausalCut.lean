-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


namespace YuanxuProof.Modules.Funflow.CausalCut

structure ImmutableCausalCut
    (EventIdentity CutIdentity : Type) where
  events : List EventIdentity
  cutIdentity : CutIdentity
  parents : EventIdentity → List EventIdentity
  everyParentCovered :
    ∀ event ∈ events,
      ∀ parent ∈ parents event, parent ∈ events

/-- Closure is checked over the supplied finite parent lists. This does not
claim that those lists authenticate causality or establish acyclicity. -/
def admitCut [DecidableEq EventIdentity] (events : List EventIdentity)
    (cutIdentity : CutIdentity) (parents : EventIdentity → List EventIdentity) :
    Option (ImmutableCausalCut EventIdentity CutIdentity) :=
  if closed : ∀ event ∈ events, ∀ parent ∈ parents event, parent ∈ events then
    some ⟨events, cutIdentity, parents, closed⟩
  else none

theorem missingParentRejected [DecidableEq EventIdentity] (events : List EventIdentity)
    (cutIdentity : CutIdentity) (parents : EventIdentity → List EventIdentity)
    (event parent : EventIdentity) (member : event ∈ events)
    (dependency : parent ∈ parents event) (missing : parent ∉ events) :
    admitCut events cutIdentity parents = none := by
  simp [admitCut, show ¬ (∀ event ∈ events, ∀ parent ∈ parents event, parent ∈ events) from
    fun closed => missing (closed event member parent dependency)]

#guard (admitCut [2] 0 (fun (_ : Nat) => [1])).isNone
#guard (admitCut [1, 2] 0 (fun (_ : Nat) => [1])).isSome


end YuanxuProof.Modules.Funflow.CausalCut
