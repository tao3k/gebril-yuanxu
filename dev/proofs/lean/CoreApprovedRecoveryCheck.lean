-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.CoreApprovedRecovery
open Lean YuanxuProof.Admission.CoreApprovedRecovery
def checkApproved (value : Json) : Except String Unit := do
  let rows ← value.getArr?
  let labels := #["warm", "joint", "policy-change", "warm-policy-change", "core-source", "cold-source", "cold-joint", "cold-omitted"]
  unless rows.size == labels.size do throw "approved recovery coverage mismatch"
  for i in [:rows.size] do
    let row ← rows[i]!.getArr?
    unless row.size == 2 do throw "approved recovery row shape mismatch"
    unless (← row[0]!.getStr?) == labels[i]! do throw "approved recovery order mismatch"
    let expected := finish (i != 5 && i != 6 && i != 7) (i != 2 && i != 3) (i != 4 && i != 5) (i != 1 && i != 6) true true
    unless (← row[1]!.getBool?) == expected do throw "native approved recovery/Lean decision mismatch"
def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    match Json.parse (← IO.FS.readFile path) >>= checkApproved with
    | .ok _ => IO.println "CORE-APPROVED-RECOVERY-CORRESPONDENCE-OK"; return 0
    | .error message => IO.eprintln message; return 1
  | _ => IO.eprintln "expected approved recovery trace"; return 2
