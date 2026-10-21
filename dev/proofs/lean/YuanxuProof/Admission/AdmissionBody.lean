-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CallPhases

namespace YuanxuProof.Admission.AdmissionBody

-- Native receiver identities/revisions projected from actual body observations.
-- A complete projection is a correspondence premise, not a supplied field list.
def quintSourceDigest : String :=
  "sha256:d3e32c9165e7638fd444580a888244b2d0618645e6583db6080b0d491e196646"
structure Read where
  receiver : Nat
  revision : Nat
  deriving DecidableEq, Repr

def current (reads : List Read) (live : Nat → Nat) : Bool :=
  reads.all (fun read => read.revision == live read.receiver)

theorem nested_window_current (outer inner : List Read) (live : Nat → Nat) :
    current (outer ++ inner) live = (current outer live && current inner live) := by
  simp [current, List.all_append]

theorem member_current (reads : List Read) (live : Nat → Nat) (read : Read)
    (accepted : current reads live = true) (selected : read ∈ reads) :
    read.revision = live read.receiver := by
  have all := List.all_eq_true.mp accepted
  simpa using all read selected

theorem changed_nested_read_rejected (outer inner : List Read) (live : Nat → Nat)
    (read : Read) (selected : read ∈ inner)
    (changed : read.revision ≠ live read.receiver) :
    current (outer ++ inner) live = false := by
  cases result : current (outer ++ inner) live with
  | false => rfl
  | true =>
    exact False.elim (changed (member_current (outer ++ inner) live read result
      (List.mem_append_right outer selected)))

def rootReturn (sourceOK : Bool) (reads : List Read) (live : Nat → Nat)
    (a b : Bool) (owner : Nat) : Bool :=
  sourceOK && current reads live && a && b && (owner == 2)

theorem accepted_preserves_all (sourceOK : Bool) (reads : List Read) (live : Nat → Nat)
    (a b : Bool) (owner : Nat)
    (accepted : rootReturn sourceOK reads live a b owner = true) :
    sourceOK = true ∧ current reads live = true ∧ a = true ∧ b = true ∧ owner = 2 := by
  simpa [rootReturn, Bool.and_eq_true, and_assoc] using accepted

theorem changed_child_prevents_root_return (sourceOK : Bool) (outer inner : List Read)
    (live : Nat → Nat) (read : Read) (selected : read ∈ inner)
    (changed : read.revision ≠ live read.receiver) (a b : Bool) (owner : Nat) :
    rootReturn sourceOK (outer ++ inner) live a b owner = false := by
  simp [rootReturn, changed_nested_read_rejected outer inner live read selected changed]

-- Fixed diagnostic order for completed bodies: source before stale reads.
-- An escaping nested adapter error is propagated, not overwritten by this pass.
def firstFault (childRejected sourceBad readsBad : Bool) : Option Nat :=
  if childRejected then some 2 else if sourceBad then some 0
  else if readsBad then some 1 else none

theorem completed_body_source_first : firstFault false true true = some 0 := rfl

theorem nested_adapter_failure_preserved (sourceBad readsBad : Bool) :
    firstFault true sourceBad readsBad = some 2 := rfl

theorem diagnostic_schedule (program : List ReadOnlyEntry.ClosedOp)
    (state : ReadOnlyEntry.Window)
    (sound : SourceWindows.Sound state.bytes state.files) :
    ReadOnlyEntry.failure (ReadOnlyEntry.execute program state) =
      ReadOnlyEntry.firstFault program state.files :=
  CallPhases.diagnostic_schedule program state sound

end YuanxuProof.Admission.AdmissionBody
