-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


/-! Erasure of projected outcome data only. No theorem here relates a native
Gerbil evaluator to an extended evaluator or proves native termination. -/
namespace YuanxuProof.PooClos.Outcomes

inductive NativeOutcome (Value Error : Type) where
  | value (result : Value)
  | failure (error : Error)
  | diverges
  deriving DecidableEq, Repr

inductive ExtendedOutcome (Value Error Control : Type) where
  | completed (native : NativeOutcome Value Error)
  | suspended (control : Control)
  | denied (control : Control)
  | cancelled (control : Control)
  deriving DecidableEq, Repr

def eraseControlAndEvidence
    {Value Error Control : Type} :
    ExtendedOutcome Value Error Control →
      Option (NativeOutcome Value Error)
  | .completed native => some native
  | .suspended _ => none
  | .denied _ => none
  | .cancelled _ => none

structure ResumptionContext
    (Root Revision Generation Demand SelfSuper History : Type) where
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  selfSuper : SelfSuper
  history : History

theorem completedOutcomeErasesToNative
    {Value Error Control : Type}
    (native : NativeOutcome Value Error) :
    eraseControlAndEvidence
      (ExtendedOutcome.completed (Control := Control) native) =
      some native := by
  rfl

theorem suspendedOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.suspended (Value := Value) (Error := Error) control) =
      none := by
  rfl

theorem deniedOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.denied (Value := Value) (Error := Error) control) =
      none := by
  rfl

theorem cancelledOutcomeHasNoSemanticErasure
    {Value Error Control : Type}
    (control : Control) :
    eraseControlAndEvidence
      (ExtendedOutcome.cancelled (Value := Value) (Error := Error) control) =
      none := by
  rfl

end YuanxuProof.PooClos.Outcomes
