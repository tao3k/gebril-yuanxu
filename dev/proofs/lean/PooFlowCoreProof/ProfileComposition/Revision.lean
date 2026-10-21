-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.ContextSlot
import PooFlowCoreProof.ModuleSystem.Graph.Cache

import PooFlowCoreProof.ModuleSystem.Selection.Requirements

namespace PooFlowCoreProof.ProfileComposition.Revision

structure RevisionContext (ProfileRevisionIdentity RootRevisionIdentity : Type) where
  profileRevision : ProfileRevisionIdentity
  rootRevision : RootRevisionIdentity
  deriving DecidableEq

open LeanPoo.Functional.Requirements

theorem profileRevisionInvalidatesCachedResult
    {ProfileRevision RootRevision Key : Type} [DecidableEq ProfileRevision] [DecidableEq RootRevision]
    {Value : RevisionContext ProfileRevision RootRevision → Key → Type}
    {keys : List Key} {Claim : ∀ c, Results Value c keys → Prop}
    {ready : Certified keys Claim} (before after : RevisionContext ProfileRevision RootRevision)
    (changed : before.profileRevision ≠ after.profileRevision) (data : Snapshot ready before) :
    (({retained := some ⟨before, data⟩} : ContextSlot ready).read after).2.2 = false := by
  apply PooFlowCoreProof.ModuleSystem.Graph.Cache.changedCutCannotHit before after _ data
  intro same
  exact changed (congrArg RevisionContext.profileRevision same)


end PooFlowCoreProof.ProfileComposition.Revision
