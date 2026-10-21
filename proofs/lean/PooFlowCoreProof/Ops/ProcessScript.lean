-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly

namespace PooFlowCoreProof.Ops.ProcessScript
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
end PooFlowCoreProof.Ops.ProcessScript
