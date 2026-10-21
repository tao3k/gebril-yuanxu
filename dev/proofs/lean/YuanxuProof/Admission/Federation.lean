-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


namespace YuanxuProof.Admission.Federation

/-- Capability projection uses explicit sets and bounded numeric lifetime/depth.
The constructor computes attenuation; callers cannot choose its laws. -/
structure Capability (CapabilityIdentity Scope ActionRole : Type) where
  identity : CapabilityIdentity
  scopes : List Scope
  actions : List ActionRole
  expiresAt : Nat
  delegationDepth : Nat

structure CapabilityAttenuation (CapabilityIdentity Scope ActionRole : Type) where
  source : Capability CapabilityIdentity Scope ActionRole
  requested : Capability CapabilityIdentity Scope ActionRole

def attenuate [DecidableEq Scope] [DecidableEq ActionRole]
    (request : CapabilityAttenuation CapabilityIdentity Scope ActionRole) :
    Capability CapabilityIdentity Scope ActionRole :=
  { identity := request.requested.identity
    scopes := request.requested.scopes.filter (· ∈ request.source.scopes)
    actions := request.requested.actions.filter (· ∈ request.source.actions)
    expiresAt := min request.requested.expiresAt request.source.expiresAt
    delegationDepth := min request.requested.delegationDepth request.source.delegationDepth }

theorem attenuationCannotAmplify [DecidableEq Scope] [DecidableEq ActionRole]
    (request : CapabilityAttenuation CapabilityIdentity Scope ActionRole) :
    (∀ scope ∈ (attenuate request).scopes, scope ∈ request.source.scopes) ∧
    (∀ action ∈ (attenuate request).actions, action ∈ request.source.actions) ∧
    (attenuate request).expiresAt ≤ request.source.expiresAt ∧
    (attenuate request).delegationDepth ≤ request.source.delegationDepth := by
  refine ⟨?_, ?_, Nat.min_le_right _ _, Nat.min_le_right _ _⟩
  · intro scope member
    simpa [attenuate] using (List.mem_filter.mp member).2
  · intro action member
    simpa [attenuate] using (List.mem_filter.mp member).2

#guard (attenuate (⟨⟨1, [1], [2], 10, 1⟩, ⟨2, [1, 3], [2, 4], 20, 9⟩⟩ :
  CapabilityAttenuation Nat Nat Nat)).scopes == [1]
#guard (attenuate (⟨⟨1, [1], [2], 10, 1⟩, ⟨2, [3], [4], 20, 9⟩⟩ :
  CapabilityAttenuation Nat Nat Nat)).actions == []


end YuanxuProof.Admission.Federation
