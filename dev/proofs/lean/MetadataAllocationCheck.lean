-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.MetadataAllocation

open Lean YuanxuProof.Admission.MetadataAllocation

def checkRow (j : Json) : Except String String := do
  let a ← j.getArr?
  unless a.size == 8 do throw "allocation observation needs eight fields"
  let name ← a[0]!.getStr?
  let parent ← a[1]!.getNat?
  let hot ← a[2]!.getNat?
  let cold ← a[3]!.getNat?
  let spec ← a[4]!.getNat?
  unless (← a[5]!.getBool?) do throw s!"revision changed: {name}"
  unless (← a[6]!.getBool?) do throw s!"reflection spine was not copied: {name}"
  unless (← a[7]!.getBool?) do throw s!"payload identity was not shared: {name}"
  unless parent == rawRoundTrip.parent && hot == rawRoundTrip.hot &&
      some cold == rawRoundTrip.cold && spec == rawRoundTrip.spec do
    throw s!"native allocation/model mismatch: {name}"
  return name

def checkTrace (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  let names ← rows.toList.mapM checkRow
  unless names == ["generated", "reflective"] do
    throw "expected both actual setter observations, once each and in order"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkTrace with
    | .error message => IO.eprintln message; return 1
    | .ok _ =>
      IO.println "METADATA-ALLOCATION-CORRESPONDENCE-OK: 2 actual native observations"
      return 0
  | _ => IO.eprintln "expected native allocation trace JSON path"; return 2
