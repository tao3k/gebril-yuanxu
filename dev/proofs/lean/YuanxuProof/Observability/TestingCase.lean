-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly

namespace YuanxuProof.Observability.TestingCase

/-! Factoring a Case's invocation does not memoize its method or result.
The state includes observable callback order; Except retains the original fault.
Scheme evaluation order and the POO lookup correspondence are executable gates.
This law does not assert a GC bound or authenticate arbitrary Scheme bodies. -/
def invoke [Monad m] (profile : P) (lookup : P → m F) (label : m L)
    (body : Unit → m A) (call : F → P → L → (Unit → m A) → m (A × R)) : m A := do
  let method ← lookup profile
  let description ← label
  let result ← call method profile description body
  pure result.1

def expanded [Monad m] (getProfile : m P) (lookup : P → m F) (label : m L)
    (body : Unit → m A) (call : F → P → L → (Unit → m A) → m (A × R)) : m A := do
  let profile ← getProfile
  let method ← lookup profile
  let description ← label
  let result ← call method profile description body
  pure result.1

theorem factoring_preserves_invocation [Monad m] (getProfile : m P)
    (lookup : P → m F) (label : m L) (body : Unit → m A)
    (call : F → P → L → (Unit → m A) → m (A × R)) :
    (do let profile ← getProfile; invoke profile lookup label body call) =
      expanded getProfile lookup label body call := rfl

namespace StageSummary

/-- Source paths belong to detailed attribution. Scope owners are selection
evidence and keep their identities even in a bounded stage summary. -/
inductive Operation (Owner Path Other : Type) where
  | initialization : Path → Operation Owner Path Other
  | initializerBody : Path → Operation Owner Path Other
  | scopeFactory : Owner → Operation Owner Path Other
  | other : Other → Operation Owner Path Other
  deriving DecidableEq

inductive Key (Owner Other : Type) where
  | initialization : Key Owner Other
  | initializerBody : Key Owner Other
  | scopeFactory : Owner → Key Owner Other
  | other : Other → Key Owner Other
  deriving DecidableEq

def key : Operation Owner Path Other → Key Owner Other
  | .initialization _ => .initialization
  | .initializerBody _ => .initializerBody
  | .scopeFactory owner => .scopeFactory owner
  | .other name => .other name

/-- Arbitrarily many files cannot add a third initializer summary key.
Native metric names add a fixed product of these two families. -/
theorem initializer_key_coverage (event : Operation Owner Path Other)
    (initializing : (∃ path, event = .initialization path) ∨
      (∃ path, event = .initializerBody path)) :
    key event = .initialization ∨ key event = .initializerBody := by
  rcases initializing with ⟨path, rfl⟩ | ⟨path, rfl⟩
  · exact Or.inl rfl
  · exact Or.inr rfl

theorem scope_identity (left right : Owner) :
    key (.scopeFactory left : Operation Owner Path Other) =
      key (.scopeFactory right : Operation Owner Path Other) ↔
      left = right := by
  simp [key]

/-- Folding path attribution never changes owner-qualified scope counts. -/
theorem scope_count [DecidableEq Owner] [DecidableEq Other]
    (events : List (Operation Owner Path Other)) (owner : Owner) :
    (events.map key).countP (fun event => decide (event = .scopeFactory owner)) =
      events.countP (fun event => match event with
        | .scopeFactory observed => decide (observed = owner)
        | _ => false) := by
  induction events with
  | nil => rfl
  | cons event rest ih =>
    cases event <;> simp [key, List.countP_cons, ih]

end StageSummary

end YuanxuProof.Observability.TestingCase
