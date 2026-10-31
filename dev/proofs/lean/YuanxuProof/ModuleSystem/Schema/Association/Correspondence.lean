-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Projection

namespace YuanxuProof.ModuleSystem.Schema.Association.Correspondence
open Projection

/-- A semantic gate, not a Scheme Module adapter. Missing/invalid receipts must
be projected with typed=false. Mandatory RHS provider requirements are explicit. -/
def checkedBoundary (done : List Nat) (index : List Anchor) (rhs retained : List Nat)
    (candidate context : Nat) (receipts : Nat → Receipt) : Except (List Nat) Unit :=
  compositionGate ((Traversal.dfsAssociations done index).map Anchor.contract ++ rhs) retained
    (fun contract => receiptGate contract candidate context (receipts contract))

theorem inherited_root_checked {Object : Type} (projection : IdentityProjection Object)
    (fuel : Nat) (object root : Object) (done : List Nat) (index : List Anchor)
    (anchor : Anchor) (rhs retained : List Nat) (context : Nat) (receipts : Nat → Receipt)
    (success : Traversal.visit projection.graph fuel (projection.encode object) [] [] = .ok done)
    (declared : anchor ∈ index) (rootAligned : anchor.root = projection.encode root)
    (path : NativePath projection.directParents object root)
    (accepted : checkedBoundary done index rhs retained (projection.encode object) context receipts = .ok ()) :
    anchor.contract ∈ retained ∧
      receiptGate anchor.contract (projection.encode object) context (receipts anchor.contract) = true := by
  have member : anchor ∈ Traversal.dfsAssociations done index := by
    apply (Traversal.successful_dfs_association_iff projection.graph fuel
      (projection.encode object) done index anchor success).mpr
    exact ⟨declared, rootAligned ▸ native_path_projects projection path⟩
  have mandatory : anchor.contract ∈ (Traversal.dfsAssociations done index).map Anchor.contract ++ rhs :=
    List.mem_append_left _ (List.mem_map.mpr ⟨anchor, member, rfl⟩)
  exact accepted_right_requirement_checked _ retained _ anchor.contract mandatory accepted

theorem inherited_root_receipt_final {Object : Type} (projection : IdentityProjection Object)
    (fuel : Nat) (object root : Object) (done : List Nat) (index : List Anchor)
    (anchor : Anchor) (rhs retained : List Nat) (context : Nat) (receipts : Nat → Receipt)
    (success : Traversal.visit projection.graph fuel (projection.encode object) [] [] = .ok done)
    (declared : anchor ∈ index) (rootAligned : anchor.root = projection.encode root)
    (path : NativePath projection.directParents object root)
    (accepted : checkedBoundary done index rhs retained (projection.encode object) context receipts = .ok ())
    (law : CoreRule (receipts anchor.contract)) :
    (receipts anchor.contract).candidate = projection.encode object ∧
    (receipts anchor.contract).context = context ∧
    (receipts anchor.contract).classified = true ∧
    (receipts anchor.contract).obligations = [] := by
  have gate := (inherited_root_checked projection fuel object root done index anchor rhs
    retained context receipts success declared rootAligned path accepted).2
  have correlation := accepted_receipt_correlated anchor.contract (projection.encode object) context _ gate
  have discharged := accepted_receipt_discharged anchor.contract (projection.encode object) context _ law gate
  exact ⟨correlation.2.1, correlation.2.2, discharged⟩

theorem rhs_requirement_checked (done : List Nat) (index : List Anchor) (rhs retained : List Nat)
    (candidate context right : Nat) (receipts : Nat → Receipt) (required : right ∈ rhs)
    (accepted : checkedBoundary done index rhs retained candidate context receipts = .ok ()) :
    right ∈ retained ∧ receiptGate right candidate context (receipts right) = true := by
  apply accepted_right_requirement_checked _ retained _ right ?_ accepted
  exact List.mem_append_right _ required

#print axioms inherited_root_receipt_final
#print axioms rhs_requirement_checked
end YuanxuProof.ModuleSystem.Schema.Association.Correspondence
