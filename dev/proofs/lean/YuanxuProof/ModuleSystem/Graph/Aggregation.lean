-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import YuanxuProof.ModuleSystem.Imports

namespace YuanxuProof.ModuleSystem.Graph.Aggregation

abbrev Selection (ProfileIdentity : Type) :=
  ProfileIdentity → Prop

def CapabilityConstraint (Action : Type) :=
  Action → Prop

def RestrictsCapability
    {Action : Type}
    (parent child : CapabilityConstraint Action) : Prop :=
  ∀ action, child action → parent action

abbrev ModuleSelections
    (moduleCount : Nat)
    (ProfileIdentity : Type) :=
  Fin moduleCount → Selection ProfileIdentity

def composeModuleSelections
    {moduleCount : Nat}
    {ProfileIdentity : Type}
    (selections : ModuleSelections moduleCount ProfileIdentity) :
    Selection ProfileIdentity :=
  fun profile => ∃ moduleIndex, selections moduleIndex profile

abbrev ModuleCapabilities
    (moduleCount : Nat)
    (Action : Type) :=
  Fin moduleCount → CapabilityConstraint Action

def intersectAllModuleCapabilities
    {moduleCount : Nat}
    {Action : Type}
    (requirements : ModuleCapabilities moduleCount Action) :
    CapabilityConstraint Action :=
  fun action => ∀ moduleIndex, requirements moduleIndex action

theorem profileWithNoContributorIsExcluded
    {moduleCount : Nat}
    {ProfileIdentity : Type}
    (selections : ModuleSelections moduleCount ProfileIdentity)
    (profile : ProfileIdentity)
    (missing : ¬ ∃ moduleIndex, selections moduleIndex profile) :
    ¬ composeModuleSelections selections profile :=
  missing

theorem emptyModuleFamilyContributesNoProfile
    {ProfileIdentity : Type}
    (selections : ModuleSelections 0 ProfileIdentity)
    (profile : ProfileIdentity) :
    ¬ composeModuleSelections selections profile := by
  intro admitted
  obtain ⟨moduleIndex, _⟩ := admitted
  exact Fin.elim0 moduleIndex

theorem effectiveCapabilityRestrictsEveryModule
    {moduleCount : Nat}
    {Action : Type}
    (requirements : ModuleCapabilities moduleCount Action)
    (moduleIndex : Fin moduleCount) :
    RestrictsCapability
      (requirements moduleIndex)
      (intersectAllModuleCapabilities requirements) := by
  intro action admitted
  exact admitted moduleIndex

theorem addingRequirementsCannotAmplifyCapability
    {moduleCount : Nat}
    {Action : Type}
    (requirements : ModuleCapabilities (moduleCount + 1) Action)
    (moduleIndex : Fin (moduleCount + 1)) :
    RestrictsCapability
      (requirements moduleIndex)
      (intersectAllModuleCapabilities requirements) :=
  effectiveCapabilityRestrictsEveryModule requirements moduleIndex

end YuanxuProof.ModuleSystem.Graph.Aggregation
