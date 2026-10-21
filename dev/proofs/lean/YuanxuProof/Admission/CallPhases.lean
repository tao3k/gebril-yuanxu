-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SerialUse

namespace YuanxuProof.Admission.CallPhases
open SnapshotLifetime

def quintSourceDigest : String :=
  "sha256:c88bf5ae9c77d23020f5d9c88aabfa9c6377a0feef96ac363e1d9736390b1c9f"

structure Frame where
  receiver : Nat
  slot : Nat
  deriving DecidableEq, Repr

def lookupFrames (cold : Bool) (receiver slot : Nat) (ambient : List Frame) : List Frame :=
  if cold then ⟨receiver, slot⟩ :: ambient else ambient
-- Actual native .get unwinds before .call applies its result.
def bodyFrames (ambient : List Frame) : List Frame := ambient

theorem cold_lookup_pushes (receiver slot : Nat) (ambient : List Frame) :
    lookupFrames true receiver slot ambient = ⟨receiver, slot⟩ :: ambient := rfl

theorem warm_lookup_adds_no_frame (receiver slot : Nat) (ambient : List Frame) :
    lookupFrames false receiver slot ambient = ambient := rfl

theorem body_restores_ambient (ambient : List Frame) : bodyFrames ambient = ambient := rfl

def bodyEdit (affected : List Nat) (ambient : List Frame) (before : Revisions) : Option Revisions :=
  commit affected ((bodyFrames ambient).map Frame.receiver) before

theorem top_level_receiver_edit_allowed (before : Revisions) :
    bodyEdit [0] [] before = some (advance [0] before) := by
  simp [bodyEdit, bodyFrames, commit]

theorem nested_receiver_edit_vetoed (before : Revisions) (slot : Nat) :
    bodyEdit [0] [⟨0, slot⟩] before = none := by
  simp [bodyEdit, bodyFrames, commit]

-- The native nested body propagates the veto exception; it cannot certify.
def certifyEdit (result : Option Revisions) (checks : Bool) : Bool :=
  match result with | none => false | some _ => checks

theorem rejected_edit_not_certified (checks : Bool) :
    certifyEdit none checks = false := rfl

theorem unrelated_demand_edit_allowed (before : Revisions) (slot : Nat) :
    bodyEdit [2] [⟨0, slot⟩] before = some (advance [2] before) ∧
    advance [2] before 0 = before 0 ∧
    advance [2] before 2 = before 2 + 1 := by
  simp [bodyEdit, bodyFrames, commit, advance]

-- Complete observation includes the function body. Lookup alone omits demand.
structure Reads where
  receiver : Nat
  demand : Nat
  deriving DecidableEq, Repr

def lookupCurrent (expected live : Reads) : Bool := expected.receiver == live.receiver

def callCurrent (expected live : Reads) : Bool := expected == live

theorem lookup_only_misses_body_change (receiver demand : Nat) :
    lookupCurrent ⟨receiver, demand⟩ ⟨receiver, demand + 1⟩ = true ∧
    callCurrent ⟨receiver, demand⟩ ⟨receiver, demand + 1⟩ = false := by
  simp [lookupCurrent, callCurrent]

theorem both_requirements_and_identity (a b : Bool) (owner : Nat)
    (expected live : SerialUse.State)
    (accepted : SerialUse.checks a b owner expected live = true) :
    a = true ∧ b = true ∧ owner = 2 ∧ expected = live :=
  SerialUse.checks_keep_requirements a b owner expected live accepted

theorem diagnostic_schedule (program : List ReadOnlyEntry.ClosedOp)
    (state : ReadOnlyEntry.Window)
    (sound : SourceWindows.Sound state.bytes state.files) :
    ReadOnlyEntry.failure (ReadOnlyEntry.execute program state) =
      ReadOnlyEntry.firstFault program state.files :=
  SerialUse.preserves_diagnostic_schedule program state sound

end YuanxuProof.Admission.CallPhases
