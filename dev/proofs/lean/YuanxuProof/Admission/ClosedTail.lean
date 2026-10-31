-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReturnTail

namespace YuanxuProof.Admission.ClosedTail

def quintSourceDigest : String :=
  "sha256:1cce84f046df2f34b002d519d38df3f028c5412684b0f1436b9382a322b992ad"

-- This is the isolated dispatcher, NOT an effect analysis of arbitrary Scheme.
inductive Observer where
  | absent
  | opaque (identity : Nat)
  deriving DecidableEq, Repr

structure Result where
  live : ReturnTail.Live
  accepted : Bool
  refused : Bool
  foreignCalls : Nat
  events : Nat
  deriving DecidableEq, Repr

def run (observer : Observer) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent) : Result :=
  match observer with
  | .opaque _ => ⟨s, false, true, 0, 0⟩
  | .absent => ⟨events.foldl ReturnTail.inspect s, a && b && (owner == 2),
                false, 0, events.length⟩

theorem opaque_refused_before_invocation (identity : Nat) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent) :
    run (.opaque identity) s a b owner events = ⟨s, false, true, 0, 0⟩ := rfl

theorem closed_tail_preserves_state (observer : Observer) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent) :
    (run observer s a b owner events).live = s := by
  cases observer <;> simp [run, ReturnTail.closed_inspection_trace]

theorem no_foreign_call (observer : Observer) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent) :
    (run observer s a b owner events).foreignCalls = 0 := by
  cases observer <;> rfl

theorem accepted_retains_requirements (observer : Observer) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent)
    (accepted : (run observer s a b owner events).accepted = true) :
    a = true ∧ b = true ∧ owner = 2 := by
  cases observer with
  | «opaque» identity => simp [run] at accepted
  | absent => simpa [run, Bool.and_eq_true, and_assoc] using accepted

theorem accepted_replay_stays_current (observer : Observer) (s : ReturnTail.Live)
    (a b : Bool) (owner : Nat) (events : List ReturnTail.InspectEvent)
    (checked : ReturnTail.mopCurrent s = true) :
    ReturnTail.mopCurrent (run observer s a b owner events).live = true := by
  simpa [closed_tail_preserves_state] using checked

-- Rejecting callbacks is not an atomic filesystem snapshot. An independent
-- writer between the first and second reads is outside run's closed alphabet.
theorem external_writer_still_requires_snapshot :
    ReturnTail.actualReturn true true true 2 ReturnTail.orderedPass = true ∧
    ReturnTail.filesCurrent ReturnTail.orderedPass.live = false := by decide

-- A return-only dispatcher cannot stop an earlier cache-exit callback that
-- writes after MOP and removes its observer before the final-source phase.
theorem return_only_misses_cleanup :
    ReturnTail.actualReturn true true true 2
      ⟨ReturnTail.lateExternal ReturnTail.origin, 0, 0⟩ = true ∧
    ReturnTail.mopCurrent (ReturnTail.lateExternal ReturnTail.origin) = false := by decide

-- Source mismatch already found before the tail is not replaced by denial.
theorem earlier_source_failure_keeps_order :
    AdmissionBody.firstFault false true true = some 0 := rfl

end YuanxuProof.Admission.ClosedTail
