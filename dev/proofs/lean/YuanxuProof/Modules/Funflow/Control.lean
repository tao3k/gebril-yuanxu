-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


namespace YuanxuProof.Modules.Funflow.Control

inductive TerminalEffect where
  | continue
  | suspend
  | deny
  | cancel
  deriving DecidableEq, Repr

inductive HandlerTransition where
  | normalReturn
  | noncontinuableBoundary
  deriving DecidableEq, Repr

def applyTerminalEffect : TerminalEffect → HandlerTransition
  | .continue => .normalReturn
  | .suspend => .noncontinuableBoundary
  | .deny => .noncontinuableBoundary
  | .cancel => .noncontinuableBoundary

structure ControlContextIdentity
    (Evaluator Process Thread Root Revision Generation Demand SafePoint
      DynamicContext IssuerWitness : Type) where
  evaluator : Evaluator
  process : Process
  thread : Thread
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  safePoint : SafePoint
  dynamicContext : DynamicContext
  issuerWitness : IssuerWitness

def EffectConstraint := TerminalEffect → Prop

def Attenuates
    (parent child : EffectConstraint) : Prop :=
  ∀ effect, child effect → parent effect

theorem continueReturnsNormally :
    applyTerminalEffect .continue = .normalReturn := by
  rfl

theorem suspendUsesNoncontinuableBoundary :
    applyTerminalEffect .suspend = .noncontinuableBoundary := by
  rfl

theorem denyUsesNoncontinuableBoundary :
    applyTerminalEffect .deny = .noncontinuableBoundary := by
  rfl

theorem cancelUsesNoncontinuableBoundary :
    applyTerminalEffect .cancel = .noncontinuableBoundary := by
  rfl

theorem attenuationIsTransitive
    (parent middle child : EffectConstraint)
    (first : Attenuates parent middle)
    (second : Attenuates middle child) :
    Attenuates parent child := by
  intro effect admitted
  exact first effect (second effect admitted)

end YuanxuProof.Modules.Funflow.Control
