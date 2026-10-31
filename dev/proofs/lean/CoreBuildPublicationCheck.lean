-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.CoreBuildPublication
open Lean YuanxuProof.Admission.CoreBuildPublication

def checkTrace (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  let labels := #["saved-cold", "saved-hot", "saved-hot-joint-replacement",
    "for-export-joint-replacement", "saved-restored", "saved-after-peer-build"]
  unless rows.size == labels.size do throw "Core publication decision coverage mismatch"
  for i in [:rows.size] do
    let row ← rows[i]!.getArr?
    unless row.size == 2 do throw "Core publication observation needs two fields"
    unless (← row[0]!.getStr?) == labels[i]! do throw "Core publication label/order mismatch"
    let actual ← row[1]!.getBool?
    let changed := i == 2 || i == 3
    let digest := if changed then "changed" else "issued"
    let gate := current "issued" digest digest
    unless actual == publish gate gate true true do
      throw "native Core publication/Lean decision mismatch"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Lean.Json.parse text >>= checkTrace with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "CORE-BUILD-PUBLICATION-CORRESPONDENCE-OK: six native decisions"; return 0
  | _ => IO.eprintln "expected Core build publication trace"; return 2
