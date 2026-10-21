-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SnapshotEntry

/-! Supported revision commits, dynamic-scope ABA and optimistic check/use gaps.
No manual purity marker or new runtime generation is assumed. -/
namespace YuanxuProof.Admission.SnapshotLifetime
open SnapshotEntry ReadOnlyEntry ReplayBoundary

def quintSourceDigest : String :=
  "sha256:8424ead206858e9d0d7b9cb92938be40fb8e2e4217a72c27759103304b693be8"
abbrev Revisions := Nat → Nat

-- Native seen-by-identity invalidation increments a selected owner once,
-- irrespective of duplicate paths through the dependency diamond.
def advance (affected : List Nat) (before : Revisions) : Revisions :=
  fun owner => if owner ∈ affected then before owner + 1 else before owner

def commit (affected active : List Nat) (before : Revisions) : Option Revisions :=
  if affected.any (fun owner => active.contains owner) then none
  else some (advance affected before)

theorem selected_owner_once (affected : List Nat) (before : Revisions) (owner : Nat)
    (selected : owner ∈ affected) : advance affected before owner = before owner + 1 := by
  simp [advance, selected]

theorem outside_closure_unchanged (affected : List Nat) (before : Revisions) (owner : Nat)
    (unselected : owner ∉ affected) : advance affected before owner = before owner := by
  simp [advance, unselected]

theorem receiver_revision_not_dependency_certificate :
    advance [1] (fun _ => 0) 0 = 0 ∧ advance [1] (fun _ => 0) 1 = 1 := by
  simp [advance]

theorem diamond_not_multiple (before : Revisions) :
    advance [0, 1, 2, 3, 3] before 3 = before 3 + 1 := by simp [advance]

theorem supported_aba_leaves_revision (affected : List Nat) (before : Revisions) (owner : Nat)
    (selected : owner ∈ affected) :
    advance affected (advance affected before) owner = before owner + 2 := by
  simp [advance, selected, Nat.add_assoc]

theorem active_closure_veto (affected active : List Nat) (before : Revisions) (owner : Nat)
    (selected : owner ∈ affected) (computing : owner ∈ active) :
    commit affected active before = none := by
  have blocked : affected.any (fun candidate => active.contains candidate) = true := by
    apply List.any_eq_true.mpr
    exact ⟨owner, selected, by simpa using computing⟩
  simp only [commit, blocked, ↓reduceIte]

structure State where
  revision : Nat
  valueRef : Nat
  observer : Option Nat
  source : Nat
  deriving DecidableEq, Repr

def cut (s : State) : Cut :=
  ⟨[0], [⟨0, 10, [some s.valueRef], "port", []⟩],
    [⟨0, s.revision, [], [], some [0], []⟩], s.observer⟩

def edit (s : State) (value : Nat) : State :=
  {s with revision := s.revision + 1, valueRef := value}

theorem different_revision_rejected (before after : State)
    (changed : before.revision ≠ after.revision) :
    guard (cut before) (cut after) = .error "MOP snapshot changed" := by
  apply guard_rejects_changed
  intro same
  have revs := congrArg (fun state => state.objects.map ObjectRow.revision) same
  have equal : before.revision = after.revision := by simpa [cut] using revs
  exact changed equal

theorem value_aba_rejected (s : State) (other : Nat) :
    (edit (edit s other) s.valueRef).valueRef = s.valueRef ∧
    guard (cut s) (cut (edit (edit s other) s.valueRef)) = .error "MOP snapshot changed" := by
  constructor
  · rfl
  · apply different_revision_rejected
    simp [edit, Nat.add_assoc]

-- This operation describes actual parameter restoration plus an independent
-- source write. It does not pretend that native parameters have an epoch.
def restoredScopeEffect (s : State) : State := {s with source := s.source + 1}

theorem scope_aba_passes_endpoints (s : State) :
    guard (cut s) (cut (restoredScopeEffect s)) = .ok (cut s) ∧
    (restoredScopeEffect s).source ≠ s.source := by
  constructor
  · simp [SnapshotEntry.guard, cut, restoredScopeEffect]
  · simp [restoredScopeEffect]

theorem initial_check_does_not_fence (s : State) (other : Nat) :
    guard (cut s) (cut s) = .ok (cut s) ∧
    guard (cut s) (cut (edit s other)) = .error "MOP snapshot changed" := by
  constructor
  · simp [SnapshotEntry.guard]
  · apply different_revision_rejected
    simp [edit]

-- A post-check can refuse authority; it cannot erase earlier external delivery.
def deliver (s : State) (sent : List Nat) : List Nat := sent ++ [s.valueRef]

theorem late_rejection_not_rollback (s : State) (other : Nat) :
    guard (cut s) (cut (edit s other)) = .error "MOP snapshot changed" ∧
    deliver s [] = [s.valueRef] := by
  constructor
  · apply different_revision_rejected
    simp [edit]
  · rfl

theorem ordered_diagnostics_retained (program : List ClosedOp) (state : Window)
    (sound : SourceWindows.Sound state.bytes state.files) :
    failure (execute program state) = firstFault program state.files :=
  ordered_failure_exact program state sound

end YuanxuProof.Admission.SnapshotLifetime
