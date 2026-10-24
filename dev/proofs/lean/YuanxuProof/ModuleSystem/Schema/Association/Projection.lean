-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Schema.Association.Traversal

namespace YuanxuProof.ModuleSystem.Schema.Association.Projection

/-- Abstract native-object domain, not an implementation of Gerbil objects.
Injectivity and exact edge extraction must be established by a native projection. -/
structure IdentityProjection (Object : Type) where
  encode : Object → Nat
  injective : Function.Injective encode
  directParents : Object → List Object
  graph : Parents
  edges : ∀ object, (directParents object).map encode = graph (encode object)

inductive NativePath {Object : Type} (parents : Object → List Object) : Object → Object → Prop where
  | self (object) : NativePath parents object object
  | step {object parent root} : parent ∈ parents object →
      NativePath parents parent root → NativePath parents object root

theorem identity_iff {Object : Type} (projection : IdentityProjection Object) (left right : Object) :
    projection.encode left = projection.encode right ↔ left = right :=
  ⟨fun same => projection.injective same, congrArg projection.encode⟩

theorem list_identity_iff {Object : Type} (projection : IdentityProjection Object)
    (left right : List Object) : left.map projection.encode = right.map projection.encode ↔ left = right := by
  constructor
  · intro same
    induction left generalizing right with
    | nil => cases right <;> simp_all
    | cons first rest ih =>
        cases right with
        | nil => simp at same
        | cons other tail =>
            have pair := List.cons.inj same
            have head := projection.injective pair.1
            have tails := ih tail pair.2
            simp [head, tails]
  · exact congrArg (List.map projection.encode)

theorem native_path_projects {Object : Type} (projection : IdentityProjection Object)
    {object root : Object} (path : NativePath projection.directParents object root) :
    Inherits projection.graph (projection.encode object) (projection.encode root) := by
  induction path with
  | self => exact .self _
  | @step object parent root member path ih =>
      apply Inherits.step (parent := projection.encode parent) ?_ ih
      rw [← projection.edges object]
      exact List.mem_map.mpr ⟨parent, member, rfl⟩

theorem projected_path_lifts {Object : Type} (projection : IdentityProjection Object)
    {node root : Nat} (path : Inherits projection.graph node root) :
    ∀ object, projection.encode object = node →
      ∃ nativeRoot, projection.encode nativeRoot = root ∧
        NativePath projection.directParents object nativeRoot := by
  induction path with
  | self node => intro object same; exact ⟨object, same, .self object⟩
  | @step node parent root member path ih =>
      intro object same
      have edge : parent ∈ (projection.directParents object).map projection.encode := by
        rw [projection.edges object, same]
        exact member
      obtain ⟨nativeParent, present, encoded⟩ := List.mem_map.mp edge
      obtain ⟨nativeRoot, final, nativePath⟩ := ih nativeParent encoded
      exact ⟨nativeRoot, final, .step present nativePath⟩

theorem path_iff {Object : Type} (projection : IdentityProjection Object) (object root : Object) :
    Inherits projection.graph (projection.encode object) (projection.encode root) ↔
      NativePath projection.directParents object root := by
  constructor
  · intro path
    obtain ⟨nativeRoot, same, nativePath⟩ := projected_path_lifts projection path object rfl
    have equal := projection.injective same
    exact equal ▸ nativePath
  · exact native_path_projects projection

/-- Bridge theorem: successful modeled DFS membership is precisely a native
parent path, PROVIDED the identity and edge-projection premises hold. -/
theorem dfs_native_path_iff {Object : Type} (projection : IdentityProjection Object)
    (fuel : Nat) (object root : Object) (done : List Nat)
    (success : Traversal.visit projection.graph fuel (projection.encode object) [] [] = .ok done) :
    projection.encode root ∈ done ↔ NativePath projection.directParents object root := by
  rw [Traversal.success_membership_iff projection.graph fuel (projection.encode object) done success]
  exact path_iff projection object root

/-- Projection of a Core receipt. typed records the actual native evidence-type
predicate. IDs are interned from actual descriptor/candidate/context values. -/
structure Receipt where
  typed : Bool
  contract : Nat
  candidate : Nat
  context : Nat
  classificationType : Nat
  classificationCandidate : Nat
  classificationContext : Nat
  classified : Bool
  obligations : List Nat
  accepted : Bool
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Repr

abbrev CoreRule (evidence : Receipt) : Prop :=
  evidence.accepted = (evidence.classified && evidence.obligations.isEmpty)

def receiptGate (contract candidate context : Nat) (evidence : Receipt) : Bool :=
  evidence.typed && (evidence.accepted &&
    (decide (evidence.contract = contract) &&
      (decide (evidence.candidate = candidate) &&
        (decide (evidence.context = context) &&
          (decide (evidence.classificationType = contract) &&
            (decide (evidence.classificationCandidate = candidate) &&
             decide (evidence.classificationContext = context)))))))

theorem receipt_gate_iff (contract candidate context : Nat) (evidence : Receipt) :
    receiptGate contract candidate context evidence = true ↔
      evidence.typed = true ∧ evidence.accepted = true ∧
      evidence.contract = contract ∧ evidence.candidate = candidate ∧
      evidence.context = context ∧ evidence.classificationType = contract ∧
      evidence.classificationCandidate = candidate ∧ evidence.classificationContext = context := by
  simp [receiptGate, Bool.and_eq_true]

theorem accepted_receipt_correlated (contract candidate context : Nat) (evidence : Receipt)
    (accepted : receiptGate contract candidate context evidence = true) :
    evidence.contract = contract ∧ evidence.candidate = candidate ∧ evidence.context = context := by
  have valid := (receipt_gate_iff contract candidate context evidence).mp accepted
  exact ⟨valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2.1⟩

theorem accepted_receipt_discharged (contract candidate context : Nat) (evidence : Receipt)
    (law : CoreRule evidence) (accepted : receiptGate contract candidate context evidence = true) :
    evidence.classified = true ∧ evidence.obligations = [] := by
  have ok := ((receipt_gate_iff contract candidate context evidence).mp accepted).2.1
  rw [law] at ok
  have both := Bool.and_eq_true_iff.mp ok
  refine ⟨both.1, ?_⟩
  cases found : evidence.obligations with
  | nil => rfl
  | cons head tail => simp [found] at both

theorem stale_candidate_refused (contract candidate context : Nat) (evidence : Receipt)
    (wrong : evidence.candidate ≠ candidate) : receiptGate contract candidate context evidence = false := by
  simp [receiptGate, wrong]

theorem stale_context_refused (contract candidate context : Nat) (evidence : Receipt)
    (wrong : evidence.context ≠ context) : receiptGate contract candidate context evidence = false := by
  simp [receiptGate, wrong]

/-- The actual responsibility-admission formula, projected from child evidence
and parent obligation results. Collection/source fidelity is a separate premise. -/
abbrev ResponsibilityRule (parent : Receipt) (children : List Receipt) (ownFailures : List Nat) : Prop :=
  parent.accepted = ((parent.classified && children.all Receipt.accepted) && ownFailures.isEmpty)

theorem responsibility_success_checks_children (contract candidate context : Nat)
    (parent : Receipt) (children : List Receipt) (ownFailures : List Nat)
    (rule : ResponsibilityRule parent children ownFailures)
    (accepted : receiptGate contract candidate context parent = true) :
    ∀ child ∈ children, child.accepted = true := by
  have ok := ((receipt_gate_iff contract candidate context parent).mp accepted).2.1
  rw [rule] at ok
  have classifiedAndChildren := (Bool.and_eq_true_iff.mp ok).1
  exact List.all_eq_true.mp (Bool.and_eq_true_iff.mp classifiedAndChildren).2

#print axioms dfs_native_path_iff
#print axioms list_identity_iff
#print axioms accepted_receipt_correlated
#print axioms accepted_receipt_discharged
end YuanxuProof.ModuleSystem.Schema.Association.Projection
