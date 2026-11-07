-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly
import YuanxuProof.Admission.Source

namespace YuanxuProof.ModuleSystem.Source.Ownership
open LeanPoo.Functional
open YuanxuProof.Admission.Source

/-! `source/directory.ss`: normalized absolute paths are projected to component
lists (filesystem normalization is external). Register enabled owners once;
resolve an imported file by nearest declared directory, never lexical prefix. -/
abbrev Path := List String
structure Owner where
  identity : String
  root : Path
  deriving Repr, DecidableEq

def register (owners : List Owner) (candidate : Owner) : Except Path (List Owner) :=
  if owners.any (fun owner => owner.root == candidate.root) then .error candidate.root
  else .ok (owners ++ [candidate])

/-- Directory is reversed for a structurally decreasing nearest-parent walk. -/
def locate (owners : List Owner) : Path → Option Owner
  | [] => owners.find? (fun owner => owner.root == [])
  | child :: parent =>
    match owners.find? (fun owner => owner.root == (child :: parent).reverse) with
    | some owner => some owner
    | none => locate owners parent

theorem exact_owner_wins (owners : List Owner) (directory : Path) (owner : Owner)
    (found : owners.find? (fun candidate => candidate.root == directory.reverse) = some owner) :
    locate owners directory = some owner := by
  cases directory with
  | nil => exact found
  | cons child parent => rw [locate, found]

theorem missing_child_uses_parent (owners : List Owner) (child : String) (parent : Path)
    (missing : owners.find? (fun candidate => candidate.root == (child :: parent).reverse) = none) :
    locate owners (child :: parent) = locate owners parent := by rw [locate, missing]

theorem located_owner_is_declared (owners : List Owner) (directory : Path) (owner : Owner)
    (found : locate owners directory = some owner) : owner ∈ owners := by
  induction directory with
  | nil => exact List.mem_of_find?_eq_some found
  | cons child parent ih =>
    simp only [locate] at found
    split at found
    · rename_i matched
      cases found
      exact List.mem_of_find?_eq_some matched
    · exact ih found

/-- Resolve at the same checked source context; an identity result cannot stand
in for a current-source certificate. Factory binds the existing source check
and directory lookup, not another global namespace registry. -/
def checkedLocate (owners : List Owner) (inputs : List (String × String)) (directory : Path) :
    Factory (String → Option String) (fun _ => Option Owner) :=
  Factory.choose (checkSources inputs) (fun _ => locate owners directory) (fun _ => none)

theorem changed_source_rejects_owner (owners : List Owner) (inputs : List (String × String))
    (directory : Path) (read : String → Option String) (input : String × String)
    (member : input ∈ inputs) (changed : read input.1 ≠ some input.2) :
    checkedLocate owners inputs directory read = none := by
  have failed : checkSources inputs read ≠ true := fun checked =>
    changedSourceCannotBeCertified _ _ input member changed ((checkSources_certifies _ _).mp checked)
  simp [checkedLocate, Factory.choose, Bool.eq_false_iff.mpr failed]

#guard locate [⟨"parent", ["modules"]⟩, ⟨"child", ["modules", "private"]⟩]
  ["implementation", "private", "modules"] == some ⟨"child", ["modules", "private"]⟩
#guard locate [⟨"wrong-prefix", ["modules", "a"]⟩] ["ab", "modules"] == none
#guard (register [⟨"one", ["modules"]⟩] ⟨"two", ["modules"]⟩).toOption == none
end YuanxuProof.ModuleSystem.Source.Ownership
