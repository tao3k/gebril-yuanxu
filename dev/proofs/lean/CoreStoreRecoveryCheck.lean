-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.CoreStoreRecovery
open Lean YuanxuProof.Admission.CoreStoreRecovery

def checkRecovery (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  let labels := #["restart-one", "restart-two", "hot-joint", "missing-static", "symlink", "mutable-joint",
                  "other-store", "unanchored", "source-change"]
  unless rows.size == labels.size do throw "store recovery coverage mismatch"
  for i in [:rows.size] do
    let row ← rows[i]!.getArr?
    unless row.size == 2 do throw "store recovery row shape mismatch"
    unless (← row[0]!.getStr?) == labels[i]! do throw "store recovery order mismatch"
    -- The unanchored negative control deliberately substitutes its own policy.
    let selected := if i == 7 then "substitute" else "selected"
    let candidate := if i == 6 || i == 7 then "substitute" else "selected"
    let filesCurrent := i != 2 && i != 3 && i != 5
    let recordCurrent := i != 2 && i != 5
    let actual := recover selected candidate true true (i != 4) (i != 8) filesCurrent recordCurrent
    unless (← row[1]!.getBool?) == actual do
      throw "native store recovery/Lean decision mismatch"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Lean.Json.parse text >>= checkRecovery with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "CORE-STORE-RECOVERY-CORRESPONDENCE-OK"; return 0
  | _ => IO.eprintln "expected recovery trace"; return 2
