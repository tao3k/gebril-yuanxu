-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import YuanxuProof.Admission.IssuerProjection

open Lean YuanxuProof.Admission YuanxuProof.Admission.IssuerProjection

def fieldNat (j : Json) (key : String) : Except String Nat := do
  (← j.getObjVal? key).getNat?
def fieldBool (j : Json) (key : String) : Except String Bool := do
  (← j.getObjVal? key).getBool?
def natList (j : Json) : Except String (List Nat) := do
  (← j.getArr?).toList.mapM Json.getNat?
def decodePayload (j : Json) : Except String IssuedRead.Payload := do
  let a ← j.getArr?
  unless a.size == 7 do throw "payload needs seven fields"
  return ⟨← a[0]!.getNat?, ← a[1]!.getNat?, ← a[2]!.getNat?,
    ← a[3]!.getNat?, ← a[4]!.getNat?, ← natList a[5]!, ← a[6]!.getNat?⟩
def optionalHandle (n : Nat) : Option Nat := if n == 0 then none else some n

structure Observation where
  name : String
  record : Record
  registered : Nat
  frozen : Option Frozen
  nativeIssued : Bool
  nativeCurrent : Bool
  revision : Nat
  instanceId : Nat
  inCache : Bool
  valueCached : Bool
  cachedValue : Nat
  miss : Bool
  effects : Nat

def decode (j : Json) : Except String Observation := do
  let registered ← fieldNat j "registered"
  let frozen ← if registered == 0 then pure none else do
    pure (some (Frozen.mk (← fieldNat j "signed-token")
      (← decodePayload (← j.getObjVal? "signed-payload"))
      (← natList (← j.getObjVal? "signed-key-shape"))))
  return {
    name := ← (← j.getObjVal? "name").getStr?
    record := ⟨← fieldNat j "token", optionalHandle (← fieldNat j "presented"),
      ← decodePayload (← j.getObjVal? "payload"), ← natList (← j.getObjVal? "key-shape")⟩
    registered := registered, frozen := frozen
    nativeIssued := ← fieldBool j "observed-issued"
    nativeCurrent := ← fieldBool j "observed-current"
    revision := ← fieldNat j "revision", instanceId := ← fieldNat j "instance"
    inCache := ← fieldBool j "in-read-cache", valueCached := ← fieldBool j "value-cached"
    cachedValue := ← fieldNat j "cached-value", miss := ← fieldBool j "miss"
    effects := ← fieldNat j "effects" }

def observedStore (o : Observation) : Store := {
  nextRecord := o.record.token + 1
  nextClosure := o.registered + 1
  registry := fun token => if token == o.record.token then optionalHandle o.registered else none
  environments := fun closure => if closure == o.registered then o.frozen else none
  readCache := if o.inCache then [o.record.token] else [] }

def projectedCurrent (o : Observation) : Bool :=
  authenticate (observedStore o) o.record &&
  (o.record.payload.revision == o.revision) &&
  (o.record.payload.instanceId == o.instanceId) &&
  (if o.miss then !o.valueCached else o.inCache && o.record.payload.value == o.cachedValue)

def checkRow (o : Observation) : Except String Unit := do
  let actualProjection := authenticate (observedStore o) o.record
  unless actualProjection == o.nativeIssued do
    throw s!"native/projected issuance mismatch: {o.name}"
  unless authenticateSingle (observedStore o) o.record == actualProjection do
    throw s!"single-closure/projected issuance mismatch: {o.name}"
  if let some frozen := o.frozen then
    unless dependencyMatches o.record.payload.dependencies
        (dependencySnapshot frozen.payload.dependencies) ==
        (o.record.payload.dependencies == frozen.payload.dependencies) do
      throw s!"ordered dependency snapshot mismatch: {o.name}"
  unless IssuedRead.issued (project (observedStore o) o.record) == actualProjection do
    throw s!"legacy projection mismatch: {o.name}"
  unless projectedCurrent o == o.nativeCurrent do
    throw s!"native/projected currentness mismatch: {o.name}"

def expectedNames : List String := ["persistent", "miss", "unsigned-copy",
  "replaced", "restored", "closure-callback-restored", "borrowed", "payload-edited",
  "callback-before", "callback-restored", "revision-before", "revision-restored"]

def checkTrace (j : Json) : Except String (List Observation) := do
  let rows ← (← j.getArr?).toList.mapM decode
  unless rows.map (·.name) == expectedNames do throw "incomplete or reordered native trace"
  for row in rows do
    checkRow row
    for earlier in rows.takeWhile (fun e => e.name != row.name) do
      if earlier.record.token == row.record.token then
        unless earlier.registered == row.registered && earlier.frozen == row.frozen do
          throw s!"original association changed: {row.name}"
  let some miss := rows[1]? | throw "missing miss observation"
  unless miss.nativeIssued && miss.nativeCurrent && !miss.inCache && !miss.valueCached do
    throw "transient miss did not remain unregistered/current"
  let some restored := rows[9]? | throw "missing restoration observation"
  unless restored.nativeIssued && restored.nativeCurrent && restored.effects > 0 do
    throw "missing restore-after-effect counterexample"
  let some changed := rows[11]? | throw "missing revision observation"
  unless changed.nativeIssued && !changed.nativeCurrent &&
      changed.revision > changed.record.payload.revision do
    throw "native revision ABA was not refused"
  return rows

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    match Json.parse text >>= checkTrace with
    | .error message => IO.eprintln message; return 1
    | .ok rows =>
      IO.println s!"ISSUER-PROJECTION-CORRESPONDENCE-OK: {rows.length} actual native observations"
      return 0
  | _ => IO.eprintln "expected native trace JSON path"; return 2
