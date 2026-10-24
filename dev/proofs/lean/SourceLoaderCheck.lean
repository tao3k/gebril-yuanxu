-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.SourceLoader
open Lean YuanxuProof.Admission.SourceLoader

def checkSourceLoader (j : Json) : Except String Unit := do
  let rows ← j.getArr?
  unless rows.size == 4 do throw "native source-loader coverage needs four observations"
  let labels := #["saved-hot-valid", "saved-hot-changed-record",
                  "direct-hot-changed-record", "reload-hot-changed-record"]
  for i in [:rows.size] do
    let a ← rows[i]!.getArr?
    unless a.size == 4 do throw "source-loader observation needs four fields"
    unless (← a[0]!.getStr?) == labels[i]! do throw "native entry coverage/order mismatch"
    let error ← a[1]!.getStr?
    let checked ← a[2]!.getNat?
    let consumed ← a[3]!.getNat?
    unless checked > 0 && consumed == 0 do throw "cached native edge missed checks or consumed new code"
    let changed := i != 0
    let edge := if i == 3 then Edge.reload else if i == 2 then Edge.direct else Edge.saved
    unless (error == "") == returnsCached edge changed do throw "native cached decision/model mismatch"
    if changed then
      unless error == "issued source or record changed" do throw "unexpected native refusal"

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkSourceLoader with
    | .error message => IO.eprintln message; return 1
    | .ok _ => IO.println "SOURCE-LOADER-CORRESPONDENCE-OK: four native cached entries"; return 0
  | _ => IO.eprintln "expected native source-loader trace"; return 2
