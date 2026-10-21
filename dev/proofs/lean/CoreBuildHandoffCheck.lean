-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.CoreBuildHandoff
open Lean YuanxuProof.Admission.CoreBuildHandoff

def checkHandoff (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  let labels := #["warm", "joint", "mismatch", "source-change"]
  unless rows.size == labels.size do throw "handoff coverage mismatch"
  for i in [:rows.size] do
    let row ← rows[i]!.getArr?
    unless row.size == 2 do throw "handoff row shape mismatch"
    unless (← row[0]!.getStr?) == labels[i]! do throw "handoff label mismatch"
    let parent := Issuance.mk "selection" "compiled" "record"
    let child := if i == 1 then Issuance.mk "selection" "changed" "changed"
      else if i == 2 then Issuance.mk "other-selection" "compiled" "record"
      else parent
    let admitted := finish (accept parent child) (i != 3) true true true
    unless (← row[1]!.getBool?) == admitted do
      throw "native Core handoff/Lean decision mismatch"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Lean.Json.parse text >>= checkHandoff with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "CORE-BUILD-HANDOFF-CORRESPONDENCE-OK"; return 0
  | _ => IO.eprintln "expected handoff trace"; return 2
