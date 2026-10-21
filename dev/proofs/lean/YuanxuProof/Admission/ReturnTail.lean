-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.AdmissionBody

namespace YuanxuProof.Admission.ReturnTail

def quintSourceDigest : String :=
  "sha256:a0e90f015509482d618dc39a21af247d9542334a07d6ff4fe29ebaaefaf5e062"
structure Live where
  receiver : Nat
  candidate : Nat
  external : Nat
  firstFile : Nat
  secondFile : Nat
  deriving DecidableEq, Repr

def mopCurrent (s : Live) : Bool :=
  (s.receiver == 0) && (s.candidate == 0) && (s.external == 0)

def filesCurrent (s : Live) : Bool := (s.firstFile == 0) && (s.secondFile == 0)

def origin : Live := ⟨0, 0, 0, 0, 0⟩

def lateReceiver (s : Live) : Live := {s with receiver := s.receiver + 1}
def lateCandidate (s : Live) : Live := {s with candidate := s.candidate + 1}
def lateExternal (s : Live) : Live := {s with external := s.external + 1}

-- Final source admission records each comparison at its own read time.
-- These values do not assert that the entire file set is current at return.
structure FilePass where
  live : Live
  firstAtRead : Nat
  secondAtRead : Nat
  deriving DecidableEq, Repr

def passAccepted (p : FilePass) : Bool := (p.firstAtRead == 0) && (p.secondAtRead == 0)

def actualReturn (replayPassed a b : Bool) (owner : Nat) (pass : FilePass) : Bool :=
  replayPassed && passAccepted pass && a && b && (owner == 2)

theorem object_tail_counterexample :
    actualReturn (mopCurrent origin) true true 2 ⟨lateReceiver origin, 0, 0⟩ = true ∧
    mopCurrent (lateReceiver origin) = false ∧
    actualReturn (mopCurrent origin) true true 2 ⟨lateCandidate origin, 0, 0⟩ = true ∧
    mopCurrent (lateCandidate origin) = false ∧
    actualReturn (mopCurrent origin) true true 2 ⟨lateExternal origin, 0, 0⟩ = true ∧
    mopCurrent (lateExternal origin) = false := by decide

theorem retained_requirements (passed a b : Bool) (owner : Nat) (pass : FilePass)
    (accepted : actualReturn passed a b owner pass = true) :
    passed = true ∧ passAccepted pass = true ∧ a = true ∧ b = true ∧ owner = 2 := by
  simpa [actualReturn, Bool.and_eq_true, and_assoc] using accepted

def orderedPass : FilePass := ⟨{origin with firstFile := 1}, 0, 0⟩

theorem earlier_file_counterexample :
    actualReturn (mopCurrent origin) true true 2 orderedPass = true ∧
    filesCurrent orderedPass.live = false := by decide

-- Structurally read-only tail events, NOT a runtime purity flag for arbitrary callbacks.
inductive InspectEvent where
  | readObject | readFirstFile | readSecondFile | countOwnInstrumentation
  deriving DecidableEq

def inspect (s : Live) (_event : InspectEvent) : Live := s

theorem closed_inspection_trace (s : Live) (events : List InspectEvent) :
    events.foldl inspect s = s := by
  induction events with
  | nil => rfl
  | cons event tail ih => simpa [List.foldl_cons, inspect] using ih

theorem quiet_tail_preserves_replay (s : Live) (events : List InspectEvent)
    (checked : mopCurrent s = true) :
    mopCurrent (events.foldl inspect s) = true := by
  simpa [closed_inspection_trace] using checked

-- Preserve the earlier diagnostic for source mismatch in a completed final pass.
theorem late_source_failure_first :
    AdmissionBody.firstFault false true true = some 0 := rfl

end YuanxuProof.Admission.ReturnTail
