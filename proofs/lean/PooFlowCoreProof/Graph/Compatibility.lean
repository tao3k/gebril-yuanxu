-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.Publication.StateMigration

namespace PooFlowCoreProof.Graph.Compatibility

open PooFlowCoreProof.Admission.Publication.StateMigration

structure CompatibilityClosureInput
    (Root Node Revision Edge ObservationCut Policy CutIdentity : Type) where
  canonicalRoot : Root
  selectedRevisions : List (Node × Revision)
  resolvedNodes : List Node
  resolvedEdges : List Edge
  observationCut : ObservationCut
  policyIdentity : Policy
  cutIdentity : CutIdentity

structure StronglyConnectedComponent
    (Node Edge ComponentIdentity : Type) where
  componentIdentity : ComponentIdentity
  nodes : List Node
  internalEdges : List Edge

structure GraphEdgeCompatibilityEvidence
    (Edge StateVersion EvidenceIdentity : Type) where
  edge : Edge
  directional :
    DirectionalCompatibilityEvidence StateVersion EvidenceIdentity

structure SCCClosureEvidence
    (Node Edge ComponentIdentity StateVersion EvidenceIdentity : Type) where
  component :
    StronglyConnectedComponent Node Edge ComponentIdentity
  requiredEdges : List Edge
  edgeEvidence :
    List (GraphEdgeCompatibilityEvidence Edge StateVersion EvidenceIdentity)
  everyRequiredEdgeCovered :
    ∀ edge ∈ requiredEdges,
      ∃ evidence ∈ edgeEvidence,
        evidence.edge = edge
  closureRelation : List Node → List Edge → Prop
  closureHolds :
    closureRelation component.nodes component.internalEdges

structure GraphCompatibilityProof
    (Root Node Revision Edge ObservationCut Policy CutIdentity
      ComponentIdentity StateVersion EvidenceIdentity ProofIdentity : Type)
    where
  input :
    CompatibilityClosureInput
      Root Node Revision Edge ObservationCut Policy CutIdentity
  components :
    List (StronglyConnectedComponent Node Edge ComponentIdentity)
  componentEvidence :
    List
      (SCCClosureEvidence
        Node Edge ComponentIdentity StateVersion EvidenceIdentity)
  everyComponentCovered :
    ∀ component ∈ components,
      ∃ evidence ∈ componentEvidence,
        evidence.component.componentIdentity = component.componentIdentity
  proofIdentity : ProofIdentity

structure CompatibilityViolation
    (Root Node Revision Edge ObservationCut Policy CutIdentity
      ViolationIdentity : Type) where
  input :
    CompatibilityClosureInput
      Root Node Revision Edge ObservationCut Policy CutIdentity
  violatingEdge : Edge
  violationIdentity : ViolationIdentity

structure CompatibilitySuspension
    (Root Node Revision Edge ObservationCut Policy CutIdentity
      SuspensionIdentity : Type) where
  input :
    CompatibilityClosureInput
      Root Node Revision Edge ObservationCut Policy CutIdentity
  missingEvidence : List Edge
  missingEvidenceNonempty : missingEvidence ≠ []
  suspensionIdentity : SuspensionIdentity

inductive CompatibilityOutcomeKind where
  | exactCutProof
  | pairwiseSummary
  | violation
  | suspension
  deriving DecidableEq, Repr

def AdmitsGraphActivation : CompatibilityOutcomeKind → Prop
  | .exactCutProof => True
  | .pairwiseSummary => False
  | .violation => False
  | .suspension => False

def IsDefinitiveViolation : CompatibilityOutcomeKind → Prop
  | .violation => True
  | .exactCutProof => False
  | .pairwiseSummary => False
  | .suspension => False

theorem pairwiseSummaryDoesNotAdmitGraphActivation :
    ¬ AdmitsGraphActivation .pairwiseSummary := by
  simp [AdmitsGraphActivation]

theorem violationFailsClosed :
    ¬ AdmitsGraphActivation .violation := by
  simp [AdmitsGraphActivation]

theorem suspensionDoesNotAdmitGraphActivation :
    ¬ AdmitsGraphActivation .suspension := by
  simp [AdmitsGraphActivation]

theorem suspensionIsNotDefinitiveViolation :
    ¬ IsDefinitiveViolation .suspension := by
  simp [IsDefinitiveViolation]

theorem exactCutProofAdmitsGraphActivation :
    AdmitsGraphActivation .exactCutProof := by
  simp [AdmitsGraphActivation]

theorem graphProofCarriesExactSemanticCut
    {Root Node Revision Edge ObservationCut Policy CutIdentity
      ComponentIdentity StateVersion EvidenceIdentity ProofIdentity : Type}
    (proof :
      GraphCompatibilityProof
        Root Node Revision Edge ObservationCut Policy CutIdentity
        ComponentIdentity StateVersion EvidenceIdentity ProofIdentity) :
    ∃ input :
        CompatibilityClosureInput
          Root Node Revision Edge ObservationCut Policy CutIdentity,
      input = proof.input := by
  exact ⟨proof.input, rfl⟩

end PooFlowCoreProof.Graph.Compatibility
