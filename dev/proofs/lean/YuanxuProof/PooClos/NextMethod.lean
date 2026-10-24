-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation
import YuanxuProof.PooClos.Dispatch

namespace YuanxuProof.PooClos.NextMethod
open LeanPoo.Functional

/-! `dispatch.ss:poo-clos-call-next-method`. Each chain contains native method
REFERENCE identities, so equal-looking methods from new generations differ.
Replacement arguments must preserve ALL qualifier chains and long-form groups. -/
structure Effective where
  around : List Nat
  before : List Nat
  primary : List Nat
  afterMethods : List Nat
  groups : List (String × List Nat)
  deriving Repr, DecidableEq

inductive Qualifier where
  | around | primary | long | before | afterMethod
  deriving Repr, DecidableEq

def allowed : Qualifier → Bool
  | .around | .primary | .long => true
  | _ => false

inductive Failure where
  | auxiliary | invalidArguments | changedApplicable | noNext
  deriving Repr, DecidableEq

/-- Argument validation and re-resolution happen before the captured next
method. Their results are explicit observations, not assumed successful checks. -/
def callNext (qualifier : Qualifier) (captured : Effective) (replacement : Option Effective)
    (argumentsValid hasNext : Bool) (invoke : Unit → Except Failure Value) : Except Failure Value :=
  if !allowed qualifier then .error .auxiliary
  else if !argumentsValid then .error .invalidArguments
  else if replacement.any (fun current => current != captured) then .error .changedApplicable
  else if hasNext then invoke () else .error .noNext

theorem auxiliary_never_invokes (captured : Effective) (replacement : Option Effective)
    (argumentsValid hasNext : Bool) (invoke : Unit → Except Failure Value) :
    callNext .before captured replacement argumentsValid hasNext invoke = .error .auxiliary := rfl

theorem changed_replacement_never_invokes (qualifier : Qualifier) (captured current : Effective)
    (permitted : allowed qualifier = true) (changed : current ≠ captured)
    (hasNext : Bool) (invoke : Unit → Except Failure Value) :
    callNext qualifier captured (some current) true hasNext invoke = .error .changedApplicable := by
  simp [callNext, permitted, changed]

/-- Even if the current primary list is unchanged, a different before/after/
around/group reference changes the effective method and blocks replacement. -/
theorem changed_before_rejected (qualifier : Qualifier) (captured current : Effective)
    (permitted : allowed qualifier = true) (changed : current.before ≠ captured.before)
    (hasNext : Bool) (invoke : Unit → Except Failure Value) :
    callNext qualifier captured (some current) true hasNext invoke = .error .changedApplicable :=
  changed_replacement_never_invokes qualifier captured current permitted
    (fun same => changed (congrArg Effective.before same)) hasNext invoke

def nextFactory (qualifier : Qualifier) (captured : Effective) (replacement : Option Effective)
    (argumentsValid hasNext : Bool) (invoke : Factory Context (fun _ => Except Failure Value)) :
    Factory Context (fun _ => Except Failure Value) :=
  fun context => callNext qualifier captured replacement argumentsValid hasNext (fun _ => invoke context)

theorem unchanged_calls_current_context (qualifier : Qualifier) (captured : Effective)
    (permitted : allowed qualifier = true) (invoke : Factory Context (fun _ => Except Failure Value))
    (context : Context) :
    nextFactory qualifier captured (some captured) true true invoke context = invoke context := by
  simp [nextFactory, callNext, permitted]

private def sample : Effective := ⟨[], [2], [1], [], []⟩
#guard (callNext .primary sample (some {sample with before := [3]}) true true
  (fun _ => .ok 7)).toOption == none
#guard (callNext .primary sample (some sample) true true (fun _ => .ok 7)).toOption == some 7
end YuanxuProof.PooClos.NextMethod
