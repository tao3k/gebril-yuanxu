-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReadOnlyEntry

/-! Selected raw-state snapshot equality is a reuse precondition, not source
currentness or history authentication. Native extraction remains an observed
correspondence, with identity-injective references and sequential stable cuts. -/
namespace YuanxuProof.Admission.SnapshotEntry
open ReadOnlyEntry ReplayBoundary SourceWindows

def quintSourceDigest : String :=
  "sha256:519c60a522a7df1fe3c15e23bb24f2e636ea25a95280af88a9fed572a5a2017a"

structure ObjectRow where
  identity : Nat
  revision : Nat
  references : List (Option Nat)
  supers : List Nat
  order : Option (List Nat)
  anchors : List (String × Nat)
  deriving DecidableEq, Repr

structure ReadRow where
  identity : Nat
  checker : Nat
  references : List (Option Nat)
  key : String
  dependencies : List Nat
  deriving DecidableEq, Repr

structure Cut where
  roots : List Nat
  reads : List ReadRow
  objects : List ObjectRow
  observer : Option Nat
  deriving DecidableEq, Repr

-- No producer purity Boolean is stored in a cut.
def guard (expected actual : Cut) : Except String Cut :=
  if expected = actual then .ok actual else .error "MOP snapshot changed"

theorem guard_accepts_exactly (expected actual result : Cut) :
    guard expected actual = .ok result ↔ expected = actual ∧ result = actual := by
  by_cases same : expected = actual <;> simp [guard, same, eq_comm]

theorem guard_rejects_changed (expected actual : Cut) (changed : expected ≠ actual) :
    guard expected actual = .error "MOP snapshot changed" := by simp [guard, changed]

/-- Reprojection is deterministic, so a passing raw-cut guard preserves every
entry analysis. This does not assume purity of an arbitrary callback. -/
theorem guarded_projection (project : Cut → Frame) (expected actual result : Cut)
    (success : guard expected actual = .ok result) (kernel : Nat) :
    inspect kernel expected.observer (project expected) =
      inspect kernel actual.observer (project actual) := by
  have same := (guard_accepts_exactly expected actual result).mp success
  rw [same.1]

/-- Once projection has yielded a closed native-entry program, no arbitrary
callback implementation can affect that program's execution. -/
theorem guarded_no_callbacks (project : Cut → Frame) (expected actual result : Cut)
    (success : guard expected actual = .ok result) (kernel : Nat)
    (closed : List ClosedOp)
    (lowered : inspect kernel expected.observer (project expected) = .ok closed)
    (callback : Exposure → Window → Except Fault Window) (state : Window) :
    executeEntries callback (entries kernel actual.observer (project actual)) state =
      execute closed state := by
  have accepted := (guarded_projection project expected actual result success kernel).symm.trans lowered
  exact lowering_independent callback _ closed accepted state

theorem ordered_first_failure (program : List ClosedOp) (state : Window)
    (sound : Sound state.bytes state.files) :
    failure (execute program state) = firstFault program state.files :=
  ordered_failure_exact program state sound

private def prepared : Cut :=
  ⟨[7], [⟨7, 10, [some 1, some 23], "bootstrap/compute-slot", []⟩],
   [⟨1, 0, [some 10], [], some [1], [("compute-slot", 23)]⟩], none⟩
private def cleared : Cut :=
  {prepared with objects := [⟨1, 0, [none], [], none, [("compute-slot", 23)]⟩]}

-- Same revision and anchor identity do not hide a changed preparation cache.
theorem clear_rejected_without_revision_change :
    (prepared.objects.map ObjectRow.revision) = (cleared.objects.map ObjectRow.revision) ∧
    guard prepared cleared = .error "MOP snapshot changed" := by
  constructor
  · rfl
  · apply guard_rejects_changed
    intro same
    have difference := congrArg (fun cut => cut.objects.map ObjectRow.order) same
    simp [prepared, cleared] at difference

theorem checker_change_rejected :
    guard prepared {prepared with reads := [⟨7, 11, [some 1, some 23], "bootstrap/compute-slot", []⟩]} =
      .error "MOP snapshot changed" := by
  apply guard_rejects_changed
  intro same
  have difference := congrArg (fun cut => cut.reads.map ReadRow.checker) same
  simp [prepared] at difference

theorem cached_value_change_rejected :
    guard prepared {prepared with reads := [⟨7, 10, [some 1, some 24], "bootstrap/compute-slot", []⟩]} =
      .error "MOP snapshot changed" := by
  apply guard_rejects_changed
  intro same
  have difference := congrArg (fun cut => cut.reads.map ReadRow.references) same
  simp [prepared] at difference

theorem observer_change_rejected :
    guard prepared {prepared with observer := some 77} = .error "MOP snapshot changed" := by
  apply guard_rejects_changed
  intro same
  have difference := congrArg Cut.observer same
  simp [prepared] at difference

theorem ancestor_change_rejected :
    guard prepared {prepared with objects := prepared.objects ++ [⟨2, 0, [], [], none, []⟩]} =
      .error "MOP snapshot changed" := by
  apply guard_rejects_changed
  intro same
  have difference := congrArg (fun cut => cut.objects.length) same
  simp [prepared] at difference

/-- Equal endpoints do not certify absence of an intervening observer. -/
theorem observer_aba_not_history :
    ([none, some 77, none] : List (Option Nat)).head? = some none ∧
    ([none, some 77, none] : List (Option Nat)).getLast? = some none ∧
    some 77 ∈ ([none, some 77, none] : List (Option Nat)) := by decide

/-- A source file can change while the MOP snapshot stays equal. Fresh source
validation still rejects; a cut guard never grants byte-cache authority. -/
theorem equal_cut_not_source_authority :
    guard prepared prepared = .ok prepared ∧
      firstFault [.source ⟨"postgresql.json", "old", "configuration source changed", "settings.port"⟩]
        (fun _ => some "new") =
      some (.admission (.source ⟨"postgresql.json", "old", "configuration source changed", "settings.port"⟩)) := by
  constructor
  · simp [guard]
  · decide

end YuanxuProof.Admission.SnapshotEntry
