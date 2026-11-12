-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.MetadataRoute

namespace YuanxuProof.Admission.IssuedRead

def quintSourceDigest : String :=
  "sha256:bc1f7a6c06c0bc84a7e7c7f6946f200b78a31f713f12eeaadeecde27ae03762b"

-- The producer retains the birth, not the user. Fields project pointer/revision
-- comparisons performed by the runtime predicate; the private birth is trusted.
structure Payload where
  receiver : Nat
  key : Nat
  revision : Nat
  instanceId : Nat
  value : Nat
  dependencies : List Nat
  checker : Nat
  deriving DecidableEq, Repr

structure Birth where
  token : Nat
  payload : Payload
  deriving DecidableEq, Repr

structure Read where
  token : Nat
  payload : Payload
  birth : Option Birth
  deriving DecidableEq, Repr

def issued (r : Read) : Bool := match r.birth with
  | none => false
  | some b => r.token == b.token && r.payload == b.payload

def mint (token : Nat) (payload : Payload) : Read :=
  ⟨token, payload, some ⟨token, payload⟩⟩

theorem runtime_mint_authenticates (token : Nat) (payload : Payload) :
    issued (mint token payload) = true := by simp [mint, issued]

theorem public_constructor_is_not_issuance (token : Nat) (payload : Payload) :
    issued ⟨token, payload, none⟩ = false := rfl

theorem borrowed_birth_rejects_another_token (token other : Nat) (payload : Payload)
    (different : other ≠ token) :
    issued ⟨other, payload, some ⟨token, payload⟩⟩ = false := by
  simp [issued, different]

theorem changed_payload_rejected (token : Nat) (before after : Payload)
    (different : after ≠ before) :
    issued ⟨token, after, some ⟨token, before⟩⟩ = false := by
  simp [issued, different]

def closureIssued (reads : List Read) : Bool := reads.all issued

-- Runtime require-current! previously called require-issued!, then the public
-- object-read-current? repeated that authentication. The private route/current
-- helpers have no caller callback between these adjacent tests. Error numbers
-- preserve unissued (0), route (1) and stale (2) priority.
def currentOnce (r : Read) (route current : Bool) : Except Nat Unit :=
  if issued r then
    if route then (if current then .ok () else .error 2) else .error 1
  else .error 0

def currentRepeated (r : Read) (route current : Bool) : Except Nat Unit :=
  if issued r then
    if issued r then
      if route then (if current then .ok () else .error 2) else .error 1
    else .error 2
  else .error 0

theorem adjacent_authentication_same_result_and_diagnostic (r : Read) (route current : Bool) :
    currentRepeated r route current = currentOnce r route current := by
  cases h : issued r <;> simp [currentRepeated, currentOnce, h]

theorem current_once_rejects_unissued_first (r : Read) (h : issued r = false)
    (route current : Bool) : currentOnce r route current = .error 0 := by
  simp [currentOnce, h]

-- This equality cannot be transported across a callback/effect. Keep the
-- second state in the return check even when the entry read was genuine.
def currentAfterEffect (before after : Read) (route current : Bool) : Except Nat Unit :=
  if issued before then
    if issued after then
      if route then (if current then .ok () else .error 2) else .error 1
    else .error 2
  else .error 0

theorem callback_authentication_cannot_be_eliminated (before after : Read)
    (valid : issued before = true) (changed : issued after = false) :
    currentAfterEffect before after true true = .error 2 ∧
      currentOnce before true true = .ok () := by
  simp [currentAfterEffect, currentOnce, valid, changed]

theorem whole_closure_authenticates_every_selected_dependency (reads : List Read)
    (h : closureIssued reads = true) (r : Read) (member : r ∈ reads) :
    issued r = true := List.all_eq_true.mp h r member

-- Registration is deliberately not an input to issued/mint. The same proof
-- applies to a transient record absent from the value/read caches.
theorem transient_mint_needs_no_registration (token : Nat) (payload : Payload) :
    issued (mint token payload) = true := runtime_mint_authenticates token payload

def preflight (reads : List Read) : Nat := if closureIssued reads then 1 else 0
theorem invalid_closure_observes_nothing (reads : List Read)
    (h : closureIssued reads = false) : preflight reads = 0 := by simp [preflight, h]

def finalAccept (reads : List Read) (route : MetadataRoute.Route)
    (a b : Bool) (owner : Nat) : Bool :=
  closureIssued reads && MetadataRoute.gate route && a && b && (owner == 2)

theorem final_accept_retains_birth_route_requirements_and_child
    (reads : List Read) (route : MetadataRoute.Route) (a b : Bool) (owner : Nat)
    (h : finalAccept reads route a b owner = true) :
    closureIssued reads = true ∧ MetadataRoute.gate route = true ∧
    a = true ∧ b = true ∧ owner = 2 := by
  simpa [finalAccept, Bool.and_eq_true, and_assoc] using h

-- Raw mutation of the private birth is outside the normal API. Merely storing
-- a struct does not create a security sandbox against runtime reflection.
theorem raw_private_birth_rewrite_can_forge (token : Nat) (payload : Payload) :
    issued ⟨token, payload, some ⟨token, payload⟩⟩ = true := by simp [issued]

theorem source_diagnosis_keeps_priority (g c : Bool) :
    CheckerOrigin.firstFault false g c = some 0 := rfl

-- The birth is record-carried, but its authority is a private identity
-- association. An arbitrary reflected replacement cannot authorize itself.
def associated (registered presented : Option Nat) (payloadOK : Bool) : Bool :=
  match registered, presented with
  | some original, some supplied => (original == supplied) && payloadOK
  | _, _ => false

theorem absent_private_association_rejects (presented : Option Nat) (ok : Bool) :
    associated none presented ok = false := by cases presented <;> rfl

theorem displaced_closure_rejects (original supplied : Nat) (ok : Bool)
    (different : original ≠ supplied) :
    associated (some original) (some supplied) ok = false := by
  simp [associated, different]

theorem authentic_closure_still_checks_payload (original : Nat) :
    associated (some original) (some original) false = false := by simp [associated]

-- Weak association lifetime is not formalized by this value model. Runtime GC
-- controls must establish that a live token retains its closure, while dead
-- token/closure cycles are not rooted by the issuer. No GC axiom is introduced.

end YuanxuProof.Admission.IssuedRead
