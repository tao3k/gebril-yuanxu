-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.StoreLowering

open Lean YuanxuProof.Admission.StoreLowering

def routeFor (name : String) : Except String Route :=
  match name with
  | "generated" => .ok .generated
  | "reflective" => .ok .reflective
  | "inline" => .ok .inlined
  | "precompiled-generated" => .ok .precompiledGenerated
  | "precompiled-reflective" => .ok .precompiledReflective
  | "precompiled-inline" => .ok .precompiledInlined
  | _ => .error s!"unknown lowered route: {name}"

def checkRow (j : Json) : Except String String := do
  let a ← j.getArr?
  unless a.size == 6 do throw "store observation needs six fields"
  let name ← a[0]!.getStr?
  let route ← routeFor name
  let expected := attempt route true
  unless (← a[1]!.getNat?) == owners.length do throw s!"owner coverage mismatch: {name}"
  unless (← a[2]!.getNat?) == expected.forcedDuring &&
      (← a[3]!.getNat?) == expected.parent &&
      (← a[4]!.getNat?) == expected.hot &&
      (← a[5]!.getNat?) == expected.cold do
    throw s!"native store/model mismatch: {name}"
  return name

def checkTrace (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  let names ← rows.toList.mapM checkRow
  unless names == ["generated", "reflective", "inline",
                   "precompiled-generated", "precompiled-reflective", "precompiled-inline"] do
    throw "expected exactly six actual lowered routes"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkTrace with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "STORE-LOWERING-CORRESPONDENCE-OK: 6 actual compiled routes"; return 0
  | _ => IO.eprintln "expected native compiled trace JSON path"; return 2
