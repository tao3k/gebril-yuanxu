-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.MetadataOwnership

namespace YuanxuProof.Admission.MetadataAllocation

def quintSourceDigest : String := "sha256:b42483a55b9ff9bc89d016ad1f8799d26f4958c0a32e8b1493d8614fa3d887f7"

-- Specification identity is shared by derivation. A fresh list spine is not a
-- fresh payload. Private allocation registration, not public owner assertions,
-- must implement this relation before it can become a production certificate.
def allocate (ledger : List (Nat × Nat)) (cell receiver : Nat) :=
  (cell, receiver) :: ledger

theorem allocation_keeps_existing (ledger : List (Nat × Nat))
    (cell receiver old : Nat) (h : old ∈ MetadataOwnership.owners ledger cell) :
    old ∈ MetadataOwnership.owners (allocate ledger cell receiver) cell := by
  simp [allocate, MetadataOwnership.owners] at *
  exact Or.inr h

theorem allocation_registers_receiver (ledger : List (Nat × Nat)) (cell receiver : Nat) :
    receiver ∈ MetadataOwnership.owners (allocate ledger cell receiver) cell := by
  simp [allocate, MetadataOwnership.owners]

structure Caches where
  spec : Nat
  parent : Nat
  hot : Nat
  cold : Option Nat
  revision : Nat
  deriving DecidableEq, Repr

def baseline : Caches := ⟨5432, 5432, 5432, none, 0⟩
def replace (s : Caches) : Caches := {s with spec := 5440}
def forceCold (s : Caches) : Caches := {s with cold := some s.spec}
def restore (s : Caches) : Caches := {s with spec := 5432}
def rawRoundTrip := restore (forceCold (replace baseline))

theorem restoration_keeps_parent_and_revision :
    rawRoundTrip.parent = baseline.parent ∧ rawRoundTrip.hot = baseline.hot ∧
    rawRoundTrip.revision = baseline.revision := by decide

theorem restoration_retains_poisoned_cold_cache :
    rawRoundTrip.cold = some 5440 ∧ rawRoundTrip.spec = 5432 := by decide

theorem restoration_is_not_invalidation :
    rawRoundTrip.cold ≠ some rawRoundTrip.spec := by decide

end YuanxuProof.Admission.MetadataAllocation
