-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly

namespace YuanxuProof.ModuleSystem.Source.Collections
open LeanPoo.Functional

/-- Filesystem regular-file observations are projected to role names. This
model checks role presence; syntax/import admission remains a separate gate. -/
structure Directory where
  name : String
  roles : List String
  deriving Repr, DecidableEq

def requiredRoles : List String := ["types", "objects", "config", "interface"]
def complete (directory : Directory) : Bool :=
  requiredRoles.all fun role => directory.roles.contains role

/-- The POO collection's exclusion slot is the supplied Factory context.
Selection does not certify a directory: each selected entry is still checked. -/
def select (directories : List Directory) :
    Factory (List String) (fun _ => List Directory) :=
  fun excluded => directories.filter fun directory => !excluded.contains directory.name

def admitRoles (directories : List Directory) :
    Factory (List String) (fun _ => Option (List Directory)) :=
  Factory.map (fun _ selected => if selected.all complete then some selected else none)
    (select directories)

theorem selected_is_not_excluded (directories : List Directory) (excluded : List String)
    (directory : Directory) (member : directory ∈ select directories excluded) :
    directory.name ∉ excluded := by
  simpa [select] using (List.mem_filter.mp member).2

theorem admission_checks_every_selected_directory (directories : List Directory)
    (excluded : List String) (result : List Directory)
    (accepted : admitRoles directories excluded = some result)
    (directory : Directory) (member : directory ∈ result) : complete directory = true := by
  unfold admitRoles Factory.map at accepted
  dsimp only at accepted
  split at accepted
  · rename_i checked
    cases accepted
    exact List.all_eq_true.mp checked directory member
  · contradiction

theorem incomplete_selected_directory_rejects (directories : List Directory)
    (excluded : List String) (directory : Directory)
    (member : directory ∈ select directories excluded) (missing : complete directory = false) :
    admitRoles directories excluded = none := by
  have failed : (select directories excluded).all complete ≠ true := by
    intro checked
    have valid := List.all_eq_true.mp checked directory member
    simp [missing] at valid
  simp [admitRoles, Factory.map, Bool.eq_false_iff.mpr failed]

theorem accepted_roles_are_present (directory : Directory) (checked : complete directory = true)
    (role : String) (required : role ∈ requiredRoles) : role ∈ directory.roles := by
  simpa using List.all_eq_true.mp checked role required

#guard admitRoles [⟨"module", requiredRoles⟩, ⟨"helper", ["interface"]⟩] ["helper"] ==
  some [⟨"module", requiredRoles⟩]
#guard admitRoles [⟨"module", requiredRoles⟩, ⟨"broken", ["interface"]⟩] ["helper"] == none
#guard admitRoles [⟨"helper", ["interface"]⟩] [] == none
end YuanxuProof.ModuleSystem.Source.Collections
