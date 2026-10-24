-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly
import LeanPoo.Functional.FunctionValidation

namespace YuanxuProof.Ops.ProcessScript
open LeanPoo.Functional

/-! `ops/func.ss` pure command preparation/environment overlay and wait-status
projection. A timeout string is the positive real's already validated native
number->string observation; clocks, spawning and watchdog delivery are external. -/
structure Script where
  command : List String
  timeoutSeconds : Option String
  deriving Repr, DecidableEq

def prepareCommand (script : Script) (arguments : List String) : List String :=
  let argv := script.command ++ arguments
  match script.timeoutSeconds with
  | none => argv
  | some seconds => ["timeout", "--verbose", "--signal=TERM", "--kill-after=5s", seconds ++ "s"] ++ argv

/-- Native batch-mode argv projection; signal delivery remains external. -/
theorem command_with_total_timeout (command arguments : List String) (seconds : String) :
    prepareCommand ⟨command, some seconds⟩ arguments =
      ["timeout", "--verbose", "--signal=TERM", "--kill-after=5s", seconds ++ "s"] ++
        command ++ arguments := rfl

theorem command_without_total_timeout (command arguments : List String) :
    prepareCommand ⟨command, none⟩ arguments = command ++ arguments := rfl

/-- Environment merge is ordinary child-over-parent POO provider composition;
it is not an alist override language. -/
def mergeEnvironment (overrides inherited : Provider Unit String (fun _ _ => String)) :=
  Provider.compose overrides inherited

theorem arguments_preserved (script : Script) (first second : List String) :
    prepareCommand script (first ++ second) = prepareCommand script first ++ second := by
  cases script with
  | mk command timeout => cases timeout <;> simp [prepareCommand, List.append_assoc]

theorem environment_override (overrides inherited : Provider Unit String (fun _ _ => String))
    (key value : String) (provided : overrides key = some (fun _ => value)) :
    mergeEnvironment overrides inherited key = some (fun _ => value) :=
  Provider.compose_provided overrides inherited key _ provided

/-! The progress fragment interprets the actual nested native Function boundary:
a zero-argument factory returns a String callback whose result is Any. The two
value constructors below suffice to distinguish a valid line from an invalid
argument; this finite interpretation does not model spawning or Scheme effects. -/
inductive ProgressValue where
  | text (value : String)
  | number (value : Nat)
  deriving Repr, DecidableEq

inductive ProgressError where
  | argument | factoryResult | source
  deriving Repr, DecidableEq

abbrev RawProgress := String → Except ProgressError ProgressValue
abbrev CheckedProgress := ProgressValue → Except ProgressError ProgressValue

inductive FactoryResult where
  | callback (body : RawProgress)
  | noncallable

def progressLine : ProgressValue → Except ProgressError String
  | .text line => .ok line
  | .number _ => .error .argument

/-- Consume the checked argument and leave the observational result unconstrained. -/
def checkedProgress (body : RawProgress) : CheckedProgress :=
  FunctionValidation.wrap progressLine Except.ok body

def checkedFactoryResult : FactoryResult → Except ProgressError CheckedProgress
  | .callback body => .ok (checkedProgress body)
  | .noncallable => .error .factoryResult

/-- Preview stores this closure; calling it performs both factory and returned
callback normalization through LeanPoo, rather than accepting a callable flag. -/
def previewProgress (factory : Unit → Except ProgressError FactoryResult) :
    Unit → Except ProgressError CheckedProgress :=
  FunctionValidation.wrap Except.ok checkedFactoryResult factory

theorem invalid_progress_argument (body : RawProgress) (number : Nat) :
    checkedProgress body (.number number) = .error .argument :=
  FunctionValidation.input_error progressLine Except.ok body _ .argument rfl

theorem valid_progress_argument (body : RawProgress) (line : String) :
    checkedProgress body (.text line) = body line := by
  cases returned : body line <;>
    simp [checkedProgress, FunctionValidation.wrap, ObjectContract.checkedAction,
      progressLine, Except.bind, returned]

theorem factory_installs_actual_checked_callback (body : RawProgress) :
    previewProgress (fun _ => .ok (.callback body)) () = .ok (checkedProgress body) := rfl

theorem noncallable_factory_result_refused :
    previewProgress (fun _ => .ok .noncallable) () = .error .factoryResult := rfl

theorem factory_source_error_preserved :
    previewProgress (fun _ => .error .source) () = .error .source := rfl

#guard match checkedProgress (fun line => .ok (.text line)) (.text "line") with
  | .ok value => decide (value = .text "line")
  | .error _ => false
#guard match checkedProgress (fun _ => .ok (.number 0)) (.number 7) with
  | .error .argument => true
  | _ => false

/-- Natural wait-status fragment of POSIX: exited status occupies the high
byte; a signal report is 128 plus its low-seven-bit signal number. -/
def exitCode (waitStatus : Nat) : Nat :=
  if waitStatus % 256 = 0 then waitStatus / 256 else 128 + waitStatus % 128

theorem exited_status (code : Nat) : exitCode (code * 256) = code := by
  simp [exitCode]

#guard prepareCommand ⟨["tool", "literal argument"], some "3"⟩ ["--flag"] ==
  ["timeout", "--verbose", "--signal=TERM", "--kill-after=5s", "3s", "tool", "literal argument", "--flag"]
#guard exitCode 9 == 137
#guard exitCode (2 * 256) == 2
end YuanxuProof.Ops.ProcessScript
