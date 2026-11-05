-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Building.SelectedPackages

/-! Managed Module roots are admitted Interface loading-configuration references,
not direct native-import application APIs or a downstream private-role list.
Applications consume init.exports via POO demand. Here dependencies denote the
existing preparation/compiler projection, including Gerbil phase edges. This model
does not implement or prove lazy scope admission. -/
namespace YuanxuProof.ModuleSystem.Building.InterfaceRoots
open YuanxuProof.ModuleSystem.Graph.TestAdmission

def moduleRoots (selected : List Nat) (interfaceOf : Nat → Nat) : List Nat :=
  selected.map interfaceOf

/-- The Lab's old library-front-end query constructs a SourceRef for one
ordinary declaration library and Interface refs for its integration directory.
Only the ordinary root belongs to the library inventory. This models the actual
metadata projection, not SourceRef admission or an installed/source partition. -/
def libraryFrontEnds (rows : List (Bool × Nat)) : List Nat :=
  (rows.filter (fun row => !row.1)).map Prod.snd

theorem literal_front_end_replaces_registry_query (entry : Nat) (interfaces : List Nat) :
    libraryFrontEnds ((false, entry) :: interfaces.map (fun path => (true, path))) =
      [entry] := by
  simp [libraryFrontEnds, List.filter_map]

/-- Replacing only that constant-valued query leaves the selected module roots,
all ordinary library roots and their native dependency closure intact. Runtime
tests establish that the real query has exactly the shape proved above. -/
theorem front_end_refactor_preserves_demands (dependencies : Nat → List Nat)
    (selected library : List Nat) (entry node : Nat) (interfaces : List Nat) :
    Demanded dependencies
      (selected ++ libraryFrontEnds ((false, entry) ::
        interfaces.map (fun path => (true, path))) ++ library) node ↔
    Demanded dependencies (selected ++ [entry] ++ library) node := by
  rw [literal_front_end_replaces_registry_query]

theorem demanded_interface_has_selected_owner (dependencies : Nat → List Nat)
    (selected : List Nat) (interfaceOf : Nat → Nat) (node : Nat)
    (demanded : Demanded dependencies (moduleRoots selected interfaceOf) node) :
    ∃ owner ∈ selected, Demanded dependencies [interfaceOf owner] node := by
  induction demanded with
  | root node member =>
    obtain ⟨owner, selectedOwner, same⟩ := List.mem_map.mp member
    exact ⟨owner, selectedOwner, Demanded.root node (by simp [same])⟩
  | dependency parent child _ edge ih =>
    obtain ⟨owner, selectedOwner, origin⟩ := ih
    exact ⟨owner, selectedOwner, Demanded.dependency parent child origin edge⟩

theorem interface_dependencies_are_selected (dependencies : Nat → List Nat)
    (selected : List Nat) (interfaceOf : Nat → Nat) (owner node : Nat)
    (member : owner ∈ selected) (demanded : Demanded dependencies [interfaceOf owner] node) :
    Demanded dependencies (moduleRoots selected interfaceOf) node := by
  induction demanded with
  | root root origin =>
    have same : root = interfaceOf owner := by simpa using origin
    apply Demanded.root
    exact List.mem_map.mpr ⟨owner, member, same.symm⟩
  | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge

theorem interface_closure_exact (dependencies : Nat → List Nat) (selected : List Nat)
    (interfaceOf : Nat → Nat) (fuel : Nat)
    (finished : (discover dependencies fuel ⟨[], moduleRoots selected interfaceOf⟩).pending = [])
    (node : Nat) :
    node ∈ (discover dependencies fuel ⟨[], moduleRoots selected interfaceOf⟩).seen ↔
      ∃ owner ∈ selected, Demanded dependencies [interfaceOf owner] node := by
  rw [completed_discovery_exact dependencies (moduleRoots selected interfaceOf) fuel finished node]
  exact ⟨demanded_interface_has_selected_owner dependencies selected interfaceOf node,
    fun ⟨owner, member, demanded⟩ =>
      interface_dependencies_are_selected dependencies selected interfaceOf owner node member demanded⟩

/-- App/build-contribution roots may be explicit without promoting role files
to separately maintained Module entrypoints. -/
theorem demanded_roots_split (dependencies : Nat → List Nat) (entries extra : List Nat)
    (node : Nat) (demanded : Demanded dependencies (entries ++ extra) node) :
    Demanded dependencies entries node ∨ Demanded dependencies extra node := by
  induction demanded with
  | root node member =>
    rcases List.mem_append.mp member with entry | contribution
    · exact Or.inl (Demanded.root node entry)
    · exact Or.inr (Demanded.root node contribution)
  | dependency parent child _ edge ih =>
    rcases ih with entry | contribution
    · exact Or.inl (Demanded.dependency parent child entry edge)
    · exact Or.inr (Demanded.dependency parent child contribution edge)

/-- Additional public/native roots come only from the selected owner declarations.
The native bridge supplies path-base admission and phase-checked Build values. -/
def contributionRoots (selected : List Nat) (contributions : Nat → List Nat) : List Nat :=
  selected.flatMap contributions

def compilationRoots (selected : List Nat) (interfaceOf : Nat → Nat)
    (contributions : Nat → List Nat) : List Nat :=
  moduleRoots selected interfaceOf ++ contributionRoots selected contributions

theorem contribution_root_has_selected_owner (selected : List Nat)
    (contributions : Nat → List Nat) (node : Nat)
    (member : node ∈ contributionRoots selected contributions) :
    ∃ owner ∈ selected, node ∈ contributions owner := by
  simpa [contributionRoots] using member

theorem demanded_compilation_has_selected_owner (dependencies : Nat → List Nat)
    (selected : List Nat) (interfaceOf : Nat → Nat) (contributions : Nat → List Nat)
    (node : Nat) (demanded : Demanded dependencies
      (compilationRoots selected interfaceOf contributions) node) :
    ∃ owner ∈ selected, Demanded dependencies (interfaceOf owner :: contributions owner) node := by
  induction demanded with
  | root node member =>
    rcases List.mem_append.mp member with base | extra
    · obtain ⟨owner, selectedOwner, same⟩ := List.mem_map.mp base
      exact ⟨owner, selectedOwner, Demanded.root node (by simp [same])⟩
    · obtain ⟨owner, selectedOwner, ownRoot⟩ := contribution_root_has_selected_owner
        selected contributions node extra
      exact ⟨owner, selectedOwner, Demanded.root node (by simp [ownRoot])⟩
  | dependency parent child _ edge ih =>
    obtain ⟨owner, selectedOwner, origin⟩ := ih
    exact ⟨owner, selectedOwner, Demanded.dependency parent child origin edge⟩

theorem selected_owner_compilation_is_demanded (dependencies : Nat → List Nat)
    (selected : List Nat) (interfaceOf : Nat → Nat) (contributions : Nat → List Nat)
    (owner node : Nat) (member : owner ∈ selected)
    (demanded : Demanded dependencies (interfaceOf owner :: contributions owner) node) :
    Demanded dependencies (compilationRoots selected interfaceOf contributions) node := by
  induction demanded with
  | root node origin =>
    apply Demanded.root
    rcases List.mem_cons.mp origin with same | extra
    · exact List.mem_append_left _ (List.mem_map.mpr ⟨owner, member, same.symm⟩)
    · exact List.mem_append_right _ (List.mem_flatMap.mpr ⟨owner, member, extra⟩)
  | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge

theorem compilation_closure_exact (dependencies : Nat → List Nat) (selected : List Nat)
    (interfaceOf : Nat → Nat) (contributions : Nat → List Nat) (fuel : Nat)
    (finished : (discover dependencies fuel
      ⟨[], compilationRoots selected interfaceOf contributions⟩).pending = []) (node : Nat) :
    node ∈ (discover dependencies fuel
      ⟨[], compilationRoots selected interfaceOf contributions⟩).seen ↔
      ∃ owner ∈ selected, Demanded dependencies (interfaceOf owner :: contributions owner) node := by
  rw [completed_discovery_exact dependencies
    (compilationRoots selected interfaceOf contributions) fuel finished node]
  exact ⟨demanded_compilation_has_selected_owner dependencies selected interfaceOf contributions node,
    fun ⟨owner, member, demanded⟩ => selected_owner_compilation_is_demanded
      dependencies selected interfaceOf contributions owner node member demanded⟩

end YuanxuProof.ModuleSystem.Building.InterfaceRoots
