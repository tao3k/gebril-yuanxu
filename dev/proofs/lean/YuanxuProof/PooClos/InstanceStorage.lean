-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly
import LeanPoo.Prototype.Compose

namespace YuanxuProof.PooClos.InstanceStorage
open LeanPoo.Functional

/-! `object-state.ss:migrated-object-storage`: retain the exact cells for
surviving object slots, allocate new unbound cells otherwise, discard removed
slots. Class-allocated slots are excluded by the effective local-slot projection. -/
structure Cell where
  reference : Nat
  value : Option Nat
  deriving Repr, DecidableEq

/-- Allocation returns actual fresh-reference observations indexed by slot.
Freshness of native allocation is an external fact, not a stored proof flag. -/
def migrate (localSlots : List String) (old : String → Option Cell)
    (allocate : String → Cell) : String → Option Cell :=
  fun slot => if slot ∈ localSlots then some ((old slot).getD (allocate slot)) else none

theorem surviving_cell_retained (slots : List String) (old : String → Option Cell)
    (allocate : String → Cell) (slot : String) (cell : Cell)
    (localSlot : slot ∈ slots) (bound : old slot = some cell) :
    migrate slots old allocate slot = some cell := by simp [migrate, localSlot, bound]

theorem removed_cell_discarded (slots : List String) (old : String → Option Cell)
    (allocate : String → Cell) (slot : String) (removed : slot ∉ slots) :
    migrate slots old allocate slot = none := by simp [migrate, removed]

theorem new_cell_allocated (slots : List String) (old : String → Option Cell)
    (allocate : String → Cell) (slot : String) (added : slot ∈ slots) (missing : old slot = none) :
    migrate slots old allocate slot = some (allocate slot) := by simp [migrate, added, missing]

structure Generation where
  classReference : Nat
  revision : Nat
  localSlots : List String
  deriving Repr, DecidableEq

structure Instance where
  generation : Generation
  storage : String → Option Cell

structure ClassLayout where
  revision : Nat
  localSlots : List String
  deriving Repr, DecidableEq

/-- The current layout is read from the instance's OWN class reference, as in
`ensure-current-instance-state!`; a caller cannot substitute a sibling class
that happens to have the same generation number. -/
def ensureCurrent (layouts : Nat → ClassLayout) (allocate : String → Cell) : Factory Instance (fun _ => Instance) :=
  fun object =>
    let layout := layouts object.generation.classReference
    let target : Generation := ⟨object.generation.classReference, layout.revision, layout.localSlots⟩
    Factory.choose (fun (_ : Unit) => object.generation.revision == target.revision)
      (fun _ => object)
      (fun _ => ⟨target, migrate layout.localSlots object.storage allocate⟩) ()

theorem current_generation_unchanged (layouts : Nat → ClassLayout) (allocate : String → Cell) (object : Instance)
    (same : object.generation.revision = (layouts object.generation.classReference).revision) :
    ensureCurrent layouts allocate object = object := by simp [ensureCurrent, Factory.choose, same]

theorem migration_reads_own_class (layouts : Nat → ClassLayout) (allocate : String → Cell) (object : Instance) :
    (ensureCurrent layouts allocate object).generation.classReference = object.generation.classReference := by
  dsimp [ensureCurrent, Factory.choose]
  split <;> rfl

#guard migrate ["keep", "new"] (fun name => if name == "keep" then some ⟨7, some 42⟩ else none)
  (fun _ => ⟨8, none⟩) "keep" == some ⟨7, some 42⟩
#guard migrate ["keep"] (fun _ => some ⟨7, some 42⟩) (fun _ => ⟨8, none⟩) "removed" == none
/-- A class owns its storage outside computed slots. Metadata refinement cannot
allocate another storage table when the receiver's memo cache is invalidated. -/
structure ClassState where
  storageReference : Nat
  directSubclasses : List Nat
  deriving Repr, DecidableEq

def registerSubclass (child : Nat) : LeanPoo.Prototype.Proto Unit ClassState ClassState :=
  fun _ inherited => { inherited with directSubclasses := child :: inherited.directSubclasses }

theorem subclass_metadata_retains_class_storage (child : Nat) (state : ClassState) :
    (registerSubclass child () state).storageReference = state.storageReference := rfl

#guard (registerSubclass 2 () ⟨7, []⟩).storageReference == 7
end YuanxuProof.PooClos.InstanceStorage

