-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.IssuedRead

namespace YuanxuProof.Admission.IssuerProjection
open IssuedRead

def sequenceSourceDigest : String := "sha256:5d1c944e7cd87562ba0ab5500fc97e2a6fcb2f96e8d1b63c399bef2e7c68990f"

-- The producer may change private storage, never the signed ordered sequence.
def dependencySnapshot (dependencies : List Nat) : Array Nat := dependencies.toArray
def dependencyMatches (current : List Nat) (saved : Array Nat) : Bool :=
  current == saved.toList

theorem private_sequence_authentication (current saved : List Nat) :
    dependencyMatches current (dependencySnapshot saved) = (current == saved) := by
  simp [dependencyMatches, dependencySnapshot]

theorem private_sequence_inspection (saved : List Nat) :
    (dependencySnapshot saved).toList = saved := by simp [dependencySnapshot]

theorem dependency_occurrences_not_deduplicated :
    dependencyMatches [1, 2] (dependencySnapshot [1, 2, 1]) = false := by decide

theorem dependency_order_not_canonicalized :
    dependencyMatches [1, 1, 2] (dependencySnapshot [1, 2, 1]) = false := by decide

def quintSourceDigest : String := "sha256:3437ee23f52802c5a24afd28b7c53fde13e744bf469b0f206131d996c4b9f504"

-- Pointer handles are an injective projection of live eq? identities. Neither
-- a public birth flag nor a successful native decision constructs this store.
structure Frozen where
  owner : Nat
  payload : Payload
  keyShape : List Nat
  deriving DecidableEq, Repr

structure Record where
  token : Nat
  presented : Option Nat
  payload : Payload
  keyShape : List Nat
  deriving DecidableEq, Repr

structure Store where
  nextRecord : Nat
  nextClosure : Nat
  registry : Nat → Option Nat
  environments : Nat → Option Frozen
  readCache : List Nat

def put {α : Type} (table : Nat → Option α) (key : Nat) (value : α) : Nat → Option α :=
  fun candidate => if candidate = key then some value else table candidate

def authenticate (s : Store) (r : Record) : Bool :=
  match s.registry r.token with
  | none => false
  | some closure =>
    if r.presented != some closure then false else
    match s.environments closure with
    | none => false
    | some frozen => r.token == frozen.owner && r.payload == frozen.payload &&
                     r.keyShape == frozen.keyShape

-- One opaque native closure captures the payload once. A false request is
-- inspection; actual RTD-checked records use the authentication branch.
-- The inspector returns copies in Scheme, not a reference to mutable metadata.
def closureRequest (frozen : Frozen) (candidate : Option Record) : Frozen ⊕ Bool :=
  match candidate with
  | none => .inl frozen
  | some r => .inr (r.token == frozen.owner && r.payload == frozen.payload &&
                   r.keyShape == frozen.keyShape)

def authenticateSingle (s : Store) (r : Record) : Bool :=
  match s.registry r.token with
  | none => false
  | some closure =>
    if r.presented != some closure then false else
    match s.environments closure with
    | none => false
    | some frozen =>
      match closureRequest frozen (some r) with
      | .inl _ => false
      | .inr accepted => accepted

theorem single_closure_authentication (s : Store) (r : Record) :
    authenticateSingle s r = authenticate s r := by
  unfold authenticateSingle authenticate
  cases s.registry r.token with
  | none => rfl
  | some closure =>
    split
    · rfl
    · cases s.environments closure <;> rfl

theorem inspection_cannot_authenticate (frozen : Frozen) :
    closureRequest frozen none ≠ .inr true := by simp [closureRequest]

theorem inspection_preserves_ordered_payload (frozen : Frozen) :
    closureRequest frozen none = .inl frozen := rfl

-- This is the old Birth model's input, now DERIVED from registry lookup,
-- original closure environment and public record fields.
def project (s : Store) (r : Record) : IssuedRead.Read :=
  let birth := do
    let closure ← s.registry r.token
    if r.presented != some closure then none else do
      let frozen ← s.environments closure
      if r.keyShape != frozen.keyShape then none
      else some (IssuedRead.Birth.mk frozen.owner frozen.payload)
  ⟨r.token, r.payload, birth⟩

theorem projection_agrees_with_verifier (s : Store) (r : Record) :
    IssuedRead.issued (project s r) = authenticate s r := by
  simp only [project, authenticate]
  cases h : s.registry r.token with
  | none => simp [h, IssuedRead.issued]
  | some closure =>
    by_cases p : r.presented = some closure
    · cases e : s.environments closure with
      | none => simp [h, p, e, IssuedRead.issued]
      | some frozen =>
        by_cases shape : r.keyShape = frozen.keyShape
        · simp [h, p, e, shape, IssuedRead.issued]
        · simp [h, p, e, shape, IssuedRead.issued]
    · simp [h, p, IssuedRead.issued]

def mint (s : Store) (payload : Payload) (shape : List Nat) (persistent : Bool) : Store × Record :=
  let r : Record := ⟨s.nextRecord, some s.nextClosure, payload, shape⟩
  let frozen : Frozen := ⟨r.token, payload, shape⟩
  let next : Store := {
    nextRecord := s.nextRecord + 1
    nextClosure := s.nextClosure + 1
    registry := put s.registry r.token s.nextClosure
    environments := put s.environments s.nextClosure frozen
    readCache := if persistent then r.token :: s.readCache else s.readCache }
  (next, r)

theorem native_mint_constructs_association (s : Store) (p : Payload) (shape : List Nat) (cache : Bool) :
    authenticate (mint s p shape cache).1 (mint s p shape cache).2 = true := by
  simp [mint, authenticate, put]

theorem mint_projects_without_birth_premise (s : Store) (p : Payload) (shape : List Nat) (cache : Bool) :
    IssuedRead.issued (project (mint s p shape cache).1 (mint s p shape cache).2) = true := by
  rw [projection_agrees_with_verifier]
  exact native_mint_constructs_association s p shape cache

theorem transient_cache_unchanged (s : Store) (p : Payload) (shape : List Nat) :
    (mint s p shape false).1.readCache = s.readCache := rfl

def Frontier (s : Store) : Prop :=
  ∀ token closure, s.registry token = some closure →
    token < s.nextRecord ∧ closure < s.nextClosure

def empty : Store := ⟨0, 0, fun _ => none, fun _ => none, []⟩

theorem empty_frontier : Frontier empty := by
  intro token closure h
  simp [empty] at h

theorem mint_preserves_frontier (s : Store) (p : Payload) (shape : List Nat)
    (cache : Bool) (h : Frontier s) : Frontier (mint s p shape cache).1 := by
  intro token closure found
  simp only [mint, put] at found ⊢
  by_cases fresh : token = s.nextRecord
  · subst token
    simp at found
    subst closure
    omega
  · simp [fresh] at found
    have old := h token closure found
    omega

theorem raw_new_record_cannot_borrow_authority (s : Store) (p : Payload) (shape : List Nat)
    (presented : Option Nat) (h : Frontier s) :
    authenticate s ⟨s.nextRecord, presented, p, shape⟩ = false := by
  have missing : s.registry s.nextRecord = none := by
    cases e : s.registry s.nextRecord with
    | none => rfl
    | some closure => exact False.elim (Nat.lt_irrefl _ (h _ _ e).1)
  simp [authenticate, missing]

theorem mint_keeps_parent_authentication (s : Store) (parent : Record)
    (p : Payload) (shape : List Nat) (cache : Bool)
    (h : Frontier s) (older : parent.token < s.nextRecord) :
    authenticate (mint s p shape cache).1 parent = authenticate s parent := by
  have distinct : parent.token ≠ s.nextRecord := Nat.ne_of_lt older
  cases original : s.registry parent.token with
  | none => simp [authenticate, mint, put, distinct, original]
  | some closure =>
    have different : closure ≠ s.nextClosure := Nat.ne_of_lt (h _ _ original).2
    simp [authenticate, mint, put, distinct, original, different]

-- SDK public construction consumes a fresh record identity, but never writes
-- the private registry. Later native allocation must not reuse that identity.
def allocateRaw (s : Store) (p : Payload) (shape : List Nat) (presented : Option Nat) : Store × Record :=
  ({s with nextRecord := s.nextRecord + 1}, ⟨s.nextRecord, presented, p, shape⟩)

theorem raw_allocation_preserves_frontier (s : Store) (p : Payload) (shape : List Nat)
    (presented : Option Nat) (h : Frontier s) : Frontier (allocateRaw s p shape presented).1 := by
  intro token closure found
  have old := h token closure found
  simp only [allocateRaw]
  omega

theorem raw_allocation_has_no_authority (s : Store) (p : Payload) (shape : List Nat)
    (presented : Option Nat) (h : Frontier s) :
    authenticate (allocateRaw s p shape presented).1 (allocateRaw s p shape presented).2 = false := by
  simpa [allocateRaw, authenticate] using raw_new_record_cannot_borrow_authority s p shape presented h

theorem later_mint_does_not_sign_public_copy (s : Store) (p q : Payload) (shape : List Nat)
    (presented : Option Nat) (h : Frontier s) :
    authenticate (mint (allocateRaw s p shape presented).1 q shape false).1
      (allocateRaw s p shape presented).2 = false := by
  rw [mint_keeps_parent_authentication _ _ q shape false
    (raw_allocation_preserves_frontier s p shape presented h)]
  · exact raw_allocation_has_no_authority s p shape presented h
  · simp [allocateRaw]

-- Public field edits cannot change the private registry/environment association.
theorem replacement_rejected (s : Store) (r : Record) (closure : Nat)
    (original : s.registry r.token = some closure)
    (different : r.presented ≠ some closure) : authenticate s r = false := by
  simp [authenticate, original, different]

theorem restore_has_same_endpoint (s : Store) (r : Record) (foreign : Option Nat) :
    authenticate s ({({r with presented := foreign}) with presented := r.presented}) =
      authenticate s r := rfl

-- Effects are separate from endpoint metadata; restoring a field does not erase
-- an effect counter. This is a counterexample to deriving read-only history.
theorem restored_endpoint_can_have_effect (s : Store) (r : Record) (effects : Nat) :
    authenticate s r = authenticate s r ∧ effects + 1 ≠ effects := by
  constructor
  · rfl
  · omega

def admit (s : Store) (r : Record) (a b : Bool) (owner : Nat) : Bool :=
  authenticate s r && a && b && (owner == 2)

theorem final_admission_keeps_both_requirements_and_child (s : Store) (r : Record)
    (a b : Bool) (owner : Nat) (h : admit s r a b owner = true) :
    authenticate s r = true ∧ a = true ∧ b = true ∧ owner = 2 := by
  simpa [admit, Bool.and_eq_true, and_assoc] using h

end YuanxuProof.Admission.IssuerProjection
