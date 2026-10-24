-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.MetadataRoute

namespace YuanxuProof.Admission.IssuedRead

def quintSourceDigest : String :=
  "sha256:4bcb921730f8e240db3c099d60e7476a3f2320b7c9bbdb29aafa34f498e9dc4c"

-- The producer retains the birth, not the user. Fields project pointer/revision
-- comparisons performed by the native predicate; the private birth is trusted.
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

theorem native_mint_authenticates (token : Nat) (payload : Payload) :
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

theorem whole_closure_authenticates_every_selected_dependency (reads : List Read)
    (h : closureIssued reads = true) (r : Read) (member : r ∈ reads) :
    issued r = true := List.all_eq_true.mp h r member

-- Registration is deliberately not an input to issued/mint. The same proof
-- applies to a transient record absent from the value/read caches.
theorem transient_mint_needs_no_registration (token : Nat) (payload : Payload) :
    issued (mint token payload) = true := native_mint_authenticates token payload

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
