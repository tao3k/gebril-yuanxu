-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SnapshotLifetime

namespace YuanxuProof.Admission.SerialUse
open SnapshotLifetime

def quintSourceDigest : String :=
  "sha256:02a496d44a17c2e391f14527f44ea1b7e15ab80ec3b30a6c5182827b58f51b44"

-- Concrete projection: frames are native cold frames; version is an external
-- authority's monotonic token, not an invented native observer generation.
structure State where
  root : Nat
  demand : Nat
  sourceVersion : Nat
  deriving DecidableEq, Repr
inductive Action where
  | affectedEdit | demandEdit | sourceEdit | read
  deriving DecidableEq, Repr

def step (cold : Bool) (s : State) : Action → State
  | .affectedEdit => if cold then s else {s with root := s.root + 1}
  | .demandEdit => {s with demand := s.demand + 1}
  | .sourceEdit => {s with sourceVersion := s.sourceVersion + 1}
  | .read => s

theorem cold_step_preserves_root (s : State) (a : Action) :
    (step true s a).root = s.root := by cases a <;> rfl

theorem serial_cold_trace_preserves_root (s : State) (actions : List Action) :
    (actions.foldl (step true) s).root = s.root := by
  induction actions generalizing s with
  | nil => rfl
  | cons a tail ih =>
    simpa only [List.foldl_cons, ih] using cold_step_preserves_root s a

theorem cold_does_not_freeze_demand (s : State) :
    (step true s .demandEdit).root = s.root ∧
    (step true s .demandEdit).demand ≠ s.demand := by
  simp [step]

theorem cold_does_not_freeze_source (s : State) :
    (step true s .sourceEdit).root = s.root ∧
    (step true s .sourceEdit).sourceVersion ≠ s.sourceVersion := by
  simp [step]

def checks (a b : Bool) (owner : Nat) (expected live : State) : Bool :=
  a && b && (owner == 2) && (expected == live)

theorem checks_keep_requirements (a b : Bool) (owner : Nat) (expected live : State)
    (accepted : checks a b owner expected live = true) :
    a = true ∧ b = true ∧ owner = 2 ∧ expected = live := by
  simpa [checks, Bool.and_eq_true, and_assoc] using accepted

-- A provider-owned atomic compare/commit is an assumption about that provider;
-- this pure relation does not implement it with a local file comparison.
def conditionalCommit (admitted : Bool) (expected live : Nat) : Bool :=
  admitted && (expected == live)

theorem changed_version_refuses_commit (admitted : Bool) (expected live : Nat)
    (changed : expected ≠ live) : conditionalCommit admitted expected live = false := by
  simp [conditionalCommit, changed]

theorem version_aba_refuses_commit (admitted : Bool) (version : Nat) :
    conditionalCommit admitted version (version + 2) = false := by
  simp [conditionalCommit]

theorem local_success_not_commit (version : Nat) :
    conditionalCommit true version version = true ∧
    conditionalCommit true version (version + 1) = false := by
  simp [conditionalCommit]

theorem preserves_diagnostic_schedule (program : List ReadOnlyEntry.ClosedOp)
    (state : ReadOnlyEntry.Window)
    (sound : SourceWindows.Sound state.bytes state.files) :
    ReadOnlyEntry.failure (ReadOnlyEntry.execute program state) =
      ReadOnlyEntry.firstFault program state.files :=
  SnapshotLifetime.ordered_diagnostics_retained program state sound
end YuanxuProof.Admission.SerialUse
