-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import YuanxuProof.ProfileComposition.Syntax
import LeanPoo.Functional.Requirements

namespace YuanxuProof.ModuleSystem.Imports

abbrev Selection (ProfileIdentity : Type) :=
  ProfileIdentity → Prop

/-- The no-alias syntax reads the Module's semantic identity, not the lexical
identifier used to access the module; explicit `as` overrides only the instance. -/
def instanceIdentity (moduleIdentity : Identity) (explicitAlias : Option Identity) : Identity :=
  explicitAlias.getD moduleIdentity

theorem defaultInstanceIdentityIsDefinitionIdentity (moduleIdentity : Identity) :
    instanceIdentity moduleIdentity none = moduleIdentity := rfl

theorem explicitAliasOverridesDefault (moduleIdentity alias : Identity) :
    instanceIdentity moduleIdentity (some alias) = alias := rfl

open LeanPoo.Functional
open LeanPoo.Functional.Requirements

/-- `profile-bundle.ss` selects each named Profile once, in first-occurrence
order, from the module-owned export index. Missing exports abort before applying
any profile factory. Preparation/retention is owned by LeanPoo. -/
def selectedProfiles (exports : Provider Context String Value) (names : List String) :=
  prepare exports names.eraseDups

theorem selectedProfiles_use_declared_exports (exports : Provider Context String Value)
    (names : List String) (factories : Factories Context Value names.eraseDups)
    (accepted : selectedProfiles exports names = .ok factories) :
    Selected exports names.eraseDups factories :=
  (prepare_ok_iff exports _ factories).mp accepted

#guard instanceIdentity "semantic-module" none == "semantic-module"
#guard instanceIdentity "semantic-module" (some "other-instance") == "other-instance"
#guard (selectedProfiles (fun name => if name == "P" then some (fun (_ : Unit) => 7) else none)
  ["P", "P"]).toOption.isSome
#guard !(selectedProfiles (fun name => if name == "P" then some (fun (_ : Unit) => 7) else none)
  ["P", "missing"]).toOption.isSome

theorem explicitInstancesRemainDistinct
    {ModuleIdentity InstanceIdentity : Type}
    (moduleIdentity : ModuleIdentity)
    (left right : InstanceIdentity)
    (distinct : left ≠ right) :
    (moduleIdentity, left) ≠ (moduleIdentity, right) := by
  intro equal
  exact distinct (Prod.mk.inj equal).2

end YuanxuProof.ModuleSystem.Imports
