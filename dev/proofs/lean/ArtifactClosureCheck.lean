-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.ArtifactClosure

open Lean YuanxuProof.Admission.ArtifactClosure

def checkArtifactRow (j : Json) : Except String (String × Bool) := do
  let a ← j.getArr?
  unless a.size == 7 do throw "artifact observation needs seven fields"
  let label ← a[0]!.getStr?
  let issued ← a[1]!.getStr?
  let observed ← a[2]!.getStr?
  let valid ← a[3]!.getBool?
  let current ← a[4]!.getBool?
  let loaded ← a[5]!.getBool?
  let accepted ← a[6]!.getBool?
  unless admit issued observed valid current loaded == accepted do
    throw s!"native artifact/model mismatch: {label}"
  return (label, accepted)

def checkArtifactTrace (j : Json) : Except String Unit := do
  let a ← j.getArr?
  let rows ← a.toList.mapM checkArtifactRow
  let expected := ["selected", "artifact-closure-changed", "artifact-closure-changed",
    "artifact-closure-changed", "unmediated-primitive", "artifact-closure-changed",
    "artifact-closure-changed", "artifact-closure-changed", "stale-compiler-input", "stale-compiler-input",
    "unselected", "callback-already-loaded"]
  unless rows.map Prod.fst == expected do throw "artifact observation coverage mismatch"
  unless rows.map Prod.snd == [true, false, false, false, false, false, false, false,
                              false, false, true, false] do
    throw "unexpected native artifact acceptance"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkArtifactTrace with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "ARTIFACT-CORRESPONDENCE-OK: 12 actual closure observations"; return 0
  | _ => IO.eprintln "expected native artifact trace path"; return 2
