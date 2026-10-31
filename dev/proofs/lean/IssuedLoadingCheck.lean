-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.IssuedLoading
open Lean YuanxuProof.Admission.IssuedLoading

def checkIssuedRow (j : Json) : Except String (String × Bool) := do
  let a ← j.getArr?
  unless a.size == 10 do throw "issued loading observation needs ten fields"
  let label ← a[0]!.getStr?
  let s ← a[1]!.getStr?
  let s' ← a[2]!.getStr?
  let u ← a[3]!.getStr?
  let u' ← a[4]!.getStr?
  let p ← a[5]!.getStr?
  let p' ← a[6]!.getStr?
  let allowed ← a[7]!.getBool?
  let consumed ← a[8]!.getNat?
  unless allows s s' u u' p p' == allowed do
    throw s!"native issued-loading/model mismatch: {label}"
  unless allowed || consumed == 0 do throw s!"rejected native load consumed code: {label}"
  if label == "private-snapshot-late-public-change" then
    unless consumed > 0 && !(← a[9]!.getBool?) do
      throw "late public replacement limitation missing"
  return (label, allowed)

def checkIssuedTrace (j : Json) : Except String Unit := do
  let a ← j.getArr?
  let rows ← a.toList.mapM checkIssuedRow
  unless rows.map Prod.fst == ["record-and-binary", "higher-object", "after-resolution",
      "dependency-at-handoff", "after-snapshot", "private-copy-before-consumption",
      "private-snapshot-late-public-change", "cached-valid", "cached-record-replacement"] do
    throw "native issued loading coverage mismatch"
  unless rows.map Prod.snd == [false, false, false, false, false, false, true, true, false] do
    throw "native issued loading decision coverage mismatch"

def checkLegacyDispatch (j : Json) : Except String Unit := do
  let a ← j.getArr?
  unless a.size == 2 do throw "legacy native dispatch observation needs two fields"
  unless (← a[0]!.getBool?) && !(← a[1]!.getBool?) do
    throw "expected observed original-SDK cached return without issuer checking"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkIssuedTrace with
    | .error message => IO.eprintln message; return 1
    | .ok _ =>
      let parent := (System.FilePath.mk path).parent.getD (System.FilePath.mk ".")
      let legacy ← IO.FS.readFile (parent / "legacy-dispatch.json")
      match Json.parse legacy >>= checkLegacyDispatch with
      | .error message => IO.eprintln message; return 1
      | .ok _ =>
        IO.println "ISSUED-LOADING-CORRESPONDENCE-OK: 9 controls; original SDK dispatch bypass retained"
        return 0
  | _ => IO.eprintln "expected native issued-loading trace path"; return 2
