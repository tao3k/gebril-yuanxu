-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly
import LeanPoo.Functional.FunctionValidation

namespace YuanxuProof.Modules.Funflow.FunctionBoundary
open LeanPoo.Functional

/-! A concrete scalar fragment of signatures.ss/task.ss/flow.ss/runner.ss.
Native Function validation owns arguments/results. Factory composition retains
the original context while the checked result feeds the next submitted task.
This interpretation does not prove arbitrary Scheme bodies, GC or OS effects. -/
inductive Value where
  | number (value : Nat)
  | text (value : String)
  deriving Repr, DecidableEq

inductive Fault where
  | input | output | source | adapter | signature
  deriving Repr, DecidableEq

def argument : Value → Except Fault Nat
  | .number n => .ok n
  | .text _ => .error .input

def result : Value → Except Fault Value
  | .number n => .ok (.number n)
  | .text _ => .error .output

abbrev Body := Nat → Except Fault Value
abbrev Checked := Value → Except Fault Value

def submit (body : Body) : Checked :=
  FunctionValidation.wrap argument result body

def thenTasks (first second : Body) : Checked :=
  Factory.bind (submit first) (fun _ outcome => fun _ => outcome.bind (submit second))

def increment : Body := fun n => .ok (.number (n + 1))
def invalidResult : Body := fun _ => .ok (.text "invalid result")

theorem invalid_argument_refuses_before_body (body : Body) (text : String) :
    submit body (.text text) = .error .input :=
  FunctionValidation.input_error argument result body _ .input rfl

theorem invalid_result_suppresses_next (next : Body) (n : Nat) :
    thenTasks invalidResult next (.number n) = .error .output := by
  simp [thenTasks, Factory.bind, submit, FunctionValidation.wrap,
    ObjectContract.checkedAction, argument, invalidResult, result, Except.bind]

theorem composed_submission (n : Nat) :
    thenTasks increment increment (.number n) = .ok (.number (n + 1 + 1)) := by
  simp [thenTasks, Factory.bind, submit, FunctionValidation.wrap,
    ObjectContract.checkedAction, argument, increment, result, Except.bind]

inductive Returned where
  | callback (body : Body)
  | invalid

def returnedCallback : Returned → Except Fault Checked
  | .callback body => .ok (submit body)
  | .invalid => .error .output

def submitFactory (factory : Nat → Except Fault Returned) :=
  FunctionValidation.wrap argument returnedCallback factory

theorem factory_returns_checked_callback (body : Body) (n : Nat) :
    submitFactory (fun _ => .ok (.callback body)) (.number n) = .ok (submit body) := by
  rfl

theorem returned_callback_refuses_bad_argument (body : Body) (text : String) :
    (returnedCallback (.callback body)).bind (fun callback => callback (.text text)) =
      .error .input := by
  exact invalid_argument_refuses_before_body body text

inductive Domain where
  | number | text
  deriving Repr, DecidableEq

structure SelectedFlow where
  input : Domain
  output : Domain
  body : Body

def admitSelected (flow : SelectedFlow) : Except Fault Checked :=
  if flow.input == .number && flow.output == .number then .ok (submit flow.body)
  else .error .signature

def submitBinder (binder : Nat → Except Fault SelectedFlow) :=
  FunctionValidation.wrap argument admitSelected binder

theorem wrong_binder_signature_refuses (body : Body) (n : Nat) :
    submitBinder (fun _ => .ok ⟨.number, .text, body⟩) (.number n) =
      .error .signature := rfl

theorem binder_installs_checked_selected_body (body : Body) (n : Nat) :
    submitBinder (fun _ => .ok ⟨.number, .number, body⟩) (.number n) =
      .ok (submit body) := rfl

/-! A declared edge does not prove its body. Every call installs native
argument/result validation, including derived callbacks and runtime results. -/
def accepts : Domain → Value → Bool
  | .number, .number _ => true
  | .text, .text _ => true
  | _, _ => false

def validateDomain (domain : Domain) (fault : Fault) (value : Value) : Except Fault Value :=
  if accepts domain value then .ok value else .error fault

structure Step where
  input : Domain
  output : Domain
  body : Checked

def checkedStep (step : Step) : Checked :=
  FunctionValidation.wrap (validateDomain step.input .input)
    (validateDomain step.output .output) step.body

theorem checked_step_output (step : Step) (input output : Value)
    (returned : checkedStep step input = .ok output) : accepts step.output output = true := by
  obtain ⟨_, raw, _, _, accepted⟩ :=
    (FunctionValidation.success _ _ _ _ _).mp returned
  unfold validateDomain at accepted
  split at accepted
  next valid => cases accepted; exact valid
  next => contradiction

def routeAccepts (input output : Domain) : List Step → Bool
  | [] => input == output
  | step :: rest => input == step.input && routeAccepts step.output output rest

def route : List Step → Checked
  | [] => Except.ok
  | step :: rest => Factory.bind (checkedStep step)
      (fun _ result => fun _ => result.bind (route rest))

def admitRoute (input output : Domain) (steps : List Step) : Except Fault Checked :=
  if routeAccepts input output steps then
    .ok (FunctionValidation.wrap (validateDomain input .input)
      (validateDomain output .output) (route steps))
  else .error .signature

theorem mismatched_route_refuses (body : Checked) :
    admitRoute .number .text [⟨.number, .number, body⟩] = .error .signature := rfl

theorem empty_route_is_checked_identity (n : Nat) :
    (admitRoute .number .number []).bind (fun run => run (.number n)) = .ok (.number n) := rfl

-- Recovery catches domain failures. Native Function faults remain faults.
def recoverSource (operation : Checked) (handler : Fault → Except Fault Value) : Checked :=
  fun input => match operation input with
    | .error .source => FunctionValidation.wrap Except.ok (validateDomain .number .output) handler .source
    | other => other

theorem recovery_result_is_checked :
    recoverSource (fun _ => .error .source) (fun _ => .ok (.text "wrong")) (.number 1) =
      .error .output := rfl

theorem type_fault_bypasses_recovery (handler : Fault → Except Fault Value) :
    recoverSource (fun _ => .error .output) handler (.number 1) = .error .output := rfl

inductive AdapterReturn where
  | receipt (requestId payload : Nat)
  | invalid
  deriving Repr, DecidableEq

def adapterResult : AdapterReturn → Except Fault (Nat × Nat)
  | .receipt id payload => .ok (id, payload)
  | .invalid => .error .adapter

def submitAdapter (body : Nat → Except Fault AdapterReturn) :=
  FunctionValidation.wrap argument adapterResult body

theorem invalid_adapter_result_refuses (n : Nat) :
    submitAdapter (fun _ => .ok .invalid) (.number n) = .error .adapter := rfl

theorem adapter_receipt_preserves_actual_values (requestId payload n : Nat) :
    submitAdapter (fun _ => .ok (.receipt requestId payload)) (.number n) =
      .ok (requestId, payload) := rfl

#guard match thenTasks increment increment (.number 3) with
  | .ok (.number 5) => true
  | _ => false
#guard match thenTasks invalidResult increment (.number 3) with
  | .error .output => true
  | _ => false
#guard match submitAdapter (fun _ => .ok .invalid) (.number 3) with
  | .error .adapter => true
  | _ => false

end YuanxuProof.Modules.Funflow.FunctionBoundary
