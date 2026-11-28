-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Source.Ownership

/-! `:build-roots` is reserved for standalone package targets outside declared
`:load-modules` windows. Any published target inside a `:load-modules` window
must resolve to a declared Yuanxu Module owner, never an ownerless native
library or a `:build-roots` bypass. -/
namespace YuanxuProof.ModuleSystem.Building.BuildRootOwnership
open YuanxuProof.ModuleSystem.Source.Ownership

/-- Path-component prefix check (never a lexical string prefix). -/
def prefixOf : Path → Path → Bool
  | [], _ => true
  | _ :: _, [] => false
  | w :: ws, t :: ts => (w == t) && prefixOf ws ts

def insideAnyWindow (windows : List Path) (target : Path) : Bool :=
  windows.any (fun window => prefixOf window target)

/-- `:build-roots` entries must stay disjoint from declared `:load-modules` windows. -/
def admitBuildRoot (windows : List Path) (root : Path) : Except Path Path :=
  if insideAnyWindow windows root then .error root else .ok root

def admitBuildRoots (windows : List Path) : List Path → Except Path (List Path)
  | [] => .ok []
  | root :: rest => do
    let admitted ← admitBuildRoot windows root
    let tail ← admitBuildRoots windows rest
    pure (admitted :: tail)

/-- Any published target inside a `:load-modules` window must be owned by a
declared Yuanxu Module; targets outside all windows remain standalone. -/
def admitPublishedTarget (windows : List Path) (owners : List Owner) (target : Path) :
    Except Path Path :=
  if insideAnyWindow windows target then
    match locate owners target.reverse with
    | some _ => .ok target
    | none => .error target
  else
    .ok target

theorem insideAnyWindow_of_mem {windows : List Path} {window target : Path}
    (member : window ∈ windows) (inside : prefixOf window target = true) :
    insideAnyWindow windows target = true := by
  exact List.any_eq_true.mpr ⟨window, member, inside⟩

theorem build_root_inside_window_rejected (windows : List Path) (window root : Path)
    (member : window ∈ windows) (inside : prefixOf window root = true) :
    admitBuildRoot windows root = .error root := by
  simp [admitBuildRoot, insideAnyWindow_of_mem member inside]

theorem build_root_outside_windows_admitted (windows : List Path) (root : Path)
    (outside : ∀ window ∈ windows, prefixOf window root = false) :
    admitBuildRoot windows root = .ok root := by
  have noneInside : insideAnyWindow windows root = false := by
    cases h : insideAnyWindow windows root with
    | false => rfl
    | true =>
      obtain ⟨window, member, inside⟩ := List.any_eq_true.mp h
      exact False.elim (by simp [outside window member] at inside)
  simp [admitBuildRoot, noneInside]

theorem admitted_build_roots_disjoint_from_windows (windows roots accepted : List Path)
    (ok : admitBuildRoots windows roots = .ok accepted) :
    accepted = roots ∧ ∀ root ∈ roots, ∀ window ∈ windows, prefixOf window root = false := by
  induction roots generalizing accepted with
  | nil =>
    simp [admitBuildRoots] at ok
    subst ok
    exact ⟨rfl, by intro _ h; cases h⟩
  | cons root rest ih =>
    simp only [admitBuildRoots, bind, Except.bind] at ok
    cases hroot : admitBuildRoot windows root with
    | error err => simp [hroot] at ok
    | ok admitted =>
      simp only [hroot] at ok
      cases hrest : admitBuildRoots windows rest with
      | error err => simp [hrest] at ok
      | ok tail =>
        simp only [hrest, pure, Except.pure, Except.ok.injEq] at ok
        have ⟨hTailEq, hTailDisjoint⟩ := ih tail hrest
        have hNotInside : insideAnyWindow windows root = false := by
          cases hin : insideAnyWindow windows root with
          | false => rfl
          | true => simp [admitBuildRoot, hin] at hroot
        have hRootEq : admitted = root := by
          have h : root = admitted := by simpa [admitBuildRoot, hNotInside] using hroot
          exact h.symm
        constructor
        · rw [← ok, hRootEq, hTailEq]
        · intro candidate hMem window hWin
          rcases List.mem_cons.mp hMem with rfl | hInRest
          · cases hPref : prefixOf window candidate with
            | false => rfl
            | true =>
              have := insideAnyWindow_of_mem hWin hPref
              simp [hNotInside] at this
          · exact hTailDisjoint candidate hInRest window hWin

theorem unowned_target_inside_window_rejected (windows : List Path) (owners : List Owner)
    (window target : Path) (member : window ∈ windows) (inside : prefixOf window target = true)
    (unowned : locate owners target.reverse = none) :
    admitPublishedTarget windows owners target = .error target := by
  simp [admitPublishedTarget, insideAnyWindow_of_mem member inside, unowned]

theorem admitted_window_target_has_declared_owner (windows : List Path) (owners : List Owner)
    (window target accepted : Path) (member : window ∈ windows)
    (inside : prefixOf window target = true)
    (ok : admitPublishedTarget windows owners target = .ok accepted) :
    accepted = target ∧ ∃ owner ∈ owners, locate owners target.reverse = some owner := by
  simp only [admitPublishedTarget, insideAnyWindow_of_mem member inside, ite_true] at ok
  cases hloc : locate owners target.reverse with
  | none => simp [hloc] at ok
  | some owner =>
    simp only [hloc, Except.ok.injEq] at ok
    exact ⟨ok.symm, owner, located_owner_is_declared owners target.reverse owner hloc, rfl⟩

theorem standalone_target_outside_windows_admitted (windows : List Path) (owners : List Owner)
    (target : Path) (outside : ∀ window ∈ windows, prefixOf window target = false) :
    admitPublishedTarget windows owners target = .ok target := by
  have noneInside : insideAnyWindow windows target = false := by
    cases h : insideAnyWindow windows target with
    | false => rfl
    | true =>
      obtain ⟨window, member, inside⟩ := List.any_eq_true.mp h
      exact False.elim (by simp [outside window member] at inside)
  simp [admitPublishedTarget, noneInside]

-- Concrete regression challenges against `:build-roots` and shadow library bypasses.
#guard (admitBuildRoot [["modules"]] ["modules", "module-authoring", "interface"]).toOption == none
#guard (admitBuildRoot [["modules"]] ["main"]).toOption == some ["main"]
#guard (admitBuildRoot [["modules"]] ["modules-extra", "main"]).toOption == some ["modules-extra", "main"]
#guard (admitPublishedTarget [["modules"]] [⟨"governance", ["modules", "governance"]⟩]
  ["modules", "loop-engine", "control", "governor"]).toOption == none
#guard (admitPublishedTarget [["modules"]] [⟨"governance", ["modules", "governance"]⟩]
  ["modules", "governance", "interface"]).toOption == some ["modules", "governance", "interface"]

end YuanxuProof.ModuleSystem.Building.BuildRootOwnership
