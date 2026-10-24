-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.Assembly

namespace YuanxuProof.Modules.Funflow.Continuation
open LeanPoo.Functional

inductive CapabilityState where
  | fresh
  | consumed
  deriving DecidableEq, Repr

def consumeOneShot : Factory CapabilityState (fun _ => Option CapabilityState) :=
  Factory.choose (fun state => state == .fresh)
    (fun _ => some .consumed) (fun _ => none)

inductive ControlDecision where
  | continue
  | suspend
  | deny
  | cancel
  | resume
  deriving DecidableEq, Repr

inductive RejectionKind where
  | controlRejection
  | nativePooFailure
  deriving DecidableEq, Repr

structure SuspensionContext
    (Evaluator Process Root Revision Generation Demand DynamicContext : Type) where
  evaluator : Evaluator
  process : Process
  root : Root
  revision : Revision
  generation : Generation
  demand : Demand
  dynamicContext : DynamicContext

theorem freshCapabilityConsumesExactlyOnce :
    consumeOneShot .fresh = some .consumed := by
  rfl

theorem consumedCapabilityCannotBeConsumedAgain :
    consumeOneShot .consumed = none := by
  rfl

theorem successfulConsumptionCannotBeRepeated (before after : CapabilityState)
    (consumed : consumeOneShot before = some after) : consumeOneShot after = none := by
  cases before <;> cases after <;> simp_all [consumeOneShot, Factory.choose]

theorem controlRejectionIsNotNativePooFailure :
    RejectionKind.controlRejection ≠ .nativePooFailure := by
  decide

end YuanxuProof.Modules.Funflow.Continuation
