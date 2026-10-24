-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.IssuerProjection

namespace YuanxuProof.Admission.RouteMutation

-- The digest is checked by the scoped Quint qualification runner.
def quintSourceDigest : String := "sha256:6c899421cb56cb2bd70504fc29d3124bdd381f1fee41795409f353325fd1e185"

-- An endpoint projection cannot encode an unobserved write history.
structure Observation where
  receiver : Nat
  revision : Nat
  route : Nat
  deriving DecidableEq

def accepted (gate : Observation → Bool) (o : Observation) (a b : Bool) : Bool :=
  gate o && a && b

theorem equal_projection_same_decision (gate : Observation → Bool)
    (before after : Observation) (h : before = after) (a b : Bool) :
    accepted gate before a b = accepted gate after a b := by rw [h]

structure RuntimeState where
  observation : Observation
  generation : Nat
  writes : Nat
  calls : Nat

-- Raw setters do not advance receiver revision or a route generation.
-- History is derived by transitions, not supplied as a purity assertion.
def rawWrite (s : RuntimeState) (route : Nat) : RuntimeState :=
  {s with observation := {s.observation with route := route}, writes := s.writes + 1}
def invoke (s : RuntimeState) : RuntimeState := {s with calls := s.calls + 1}
def roundTrip (s : RuntimeState) : RuntimeState :=
  rawWrite (invoke (rawWrite s 1)) s.observation.route

theorem raw_restore_keeps_observation (s : RuntimeState) :
    (roundTrip s).observation = s.observation := by
  cases s with
  | mk o g w c => cases o; rfl

theorem raw_restore_keeps_generation (s : RuntimeState) :
    (roundTrip s).generation = s.generation := rfl

theorem raw_restore_retains_history (s : RuntimeState) :
    (roundTrip s).writes = s.writes + 2 ∧ (roundTrip s).calls = s.calls + 1 := by
  exact ⟨rfl, rfl⟩

theorem restored_route_same_decision (gate : Observation → Bool)
    (s : RuntimeState) (a b : Bool) :
    accepted gate (roundTrip s).observation a b = accepted gate s.observation a b := by
  rw [raw_restore_keeps_observation]

-- Conditional design, NOT a claim that runtime.slot-set! advances an epoch.
def generationGate (entry exit : Nat) : Bool := entry == exit

theorem tracked_write_rejected (entry exit : Nat) (advanced : entry < exit) :
    generationGate entry exit = false := by
  apply Bool.eq_false_iff.mpr
  intro h
  have eq : entry = exit := by simpa [generationGate] using h
  exact (Nat.ne_of_lt advanced) eq

theorem restoring_route_cannot_restore_generation (entry writes : Nat) (h : 0 < writes) :
    generationGate entry (entry + writes) = false := by
  apply tracked_write_rejected
  exact Nat.lt_add_of_pos_right h

theorem untracked_write_defeats_generation (s : RuntimeState) :
    generationGate s.generation (roundTrip s).generation = true ∧
      s.calls < (roundTrip s).calls := by
  constructor
  · simp [generationGate, raw_restore_keeps_generation]
  · exact Nat.lt_succ_self s.calls

-- Same native pre-write guard as check-object-edit's active receiver branch.
def supportedEdit (active : Bool) (revision : Nat) : Option Nat :=
  if active then none else some (revision + 1)

theorem active_edit_refused_before_write (revision : Nat) :
    supportedEdit true revision = none := rfl

theorem accepted_keeps_both (gate : Observation → Bool) (o : Observation)
    (a b : Bool) (h : accepted gate o a b = true) : a = true ∧ b = true := by
  simp only [accepted, Bool.and_eq_true] at h
  exact ⟨h.1.2, h.2⟩

end YuanxuProof.Admission.RouteMutation
