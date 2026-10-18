-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.Publication.ActiveHead
import PooFlowCoreProof.Admission.Publication.Activation

namespace PooFlowCoreProof.Admission.Publication.Retirement

open PooFlowCoreProof.Admission.Publication.ActiveHead
open PooFlowCoreProof.Admission.Publication.Activation

structure RetirementPrecondition
    (Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity : Type) where
  activeHead :
    ActiveHeadObservation
      Scope Generation Version AdapterProtocol ObservationReceipt
  retiringGeneration : Generation
  noLongerSelected :
    retiringGeneration ≠ activeHead.selectedGeneration
  fenceIdentity : FenceIdentity
  retirementReceiptIdentity : RetirementReceiptIdentity

structure QuiescenceWitness
    (Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity : Type) where
  retirement :
    RetirementPrecondition
      Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity
  livePins : List PinIdentity
  outstandingObligations : List ObligationIdentity
  noLivePins : livePins = []
  noOutstandingObligations : outstandingObligations = []
  quiescenceReceiptIdentity : QuiescenceReceiptIdentity

structure ConsumerEvidenceQuiescenceBridge
    (Consumer Scope Generation Version
      PublicationReceiptIdentity ObservationReceiptIdentity
      ArtifactIdentity PreparationReceiptIdentity
      ActivationEpoch ActivationReceiptIdentity CompletionReceiptIdentity
      AdapterProtocol HeadObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity : Type) where
  activation :
    LocalActivationReceipt
      Consumer Scope Generation Version
      PublicationReceiptIdentity ObservationReceiptIdentity
      ArtifactIdentity PreparationReceiptIdentity
      ActivationEpoch ActivationReceiptIdentity
  completion :
    RolloutCompletionReceipt
      Consumer Scope Generation Version
      PublicationReceiptIdentity ObservationReceiptIdentity
      ArtifactIdentity PreparationReceiptIdentity
      ActivationEpoch ActivationReceiptIdentity
      CompletionReceiptIdentity
  quiescence :
    QuiescenceWitness
      Scope Generation Version AdapterProtocol HeadObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity
  activationTargetsRetiringGeneration :
    activation.activatedGeneration =
      quiescence.retirement.retiringGeneration
  completionCoversConsumer :
    activation.preparation.observation.consumerIdentity ∈
      completion.requiredConsumers
  activationPinIdentity : PinIdentity
  activationPinDrained :
    activationPinIdentity ∉ quiescence.livePins
  completionObligationIdentity : ObligationIdentity
  completionObligationDischarged :
    completionObligationIdentity ∉ quiescence.outstandingObligations

structure MaterializationOwnership
    (Generation Materialization Owner : Type) where
  generationIdentity : Generation
  materializationIdentity : Materialization
  ownerIdentity : Owner
  belongsToGeneration : Materialization → Generation → Prop
  ownershipHolds :
    belongsToGeneration materializationIdentity generationIdentity

structure ReclamationAdmission
    (Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity
      Materialization Owner ReclamationReceiptIdentity : Type) where
  quiescence :
    QuiescenceWitness
      Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity
  materializations :
    List (MaterializationOwnership Generation Materialization Owner)
  allMaterializationsBelongToRetiredGeneration :
    ∀ ownership ∈ materializations,
      ownership.generationIdentity =
        quiescence.retirement.retiringGeneration
  semanticGenerationPresent : Generation → Prop
  generationRecordPreserved :
    semanticGenerationPresent quiescence.retirement.retiringGeneration
  reclamationReceiptIdentity : ReclamationReceiptIdentity

inductive LifecycleEvidenceKind where
  | authoritativeHeadObservation
  | retirementFence
  | quiescenceWitness
  | reclamationAdmission
  deriving DecidableEq, Repr

def EstablishesRetirement : LifecycleEvidenceKind → Prop
  | .retirementFence => True
  | .quiescenceWitness => True
  | .reclamationAdmission => True
  | .authoritativeHeadObservation => False

def EstablishesQuiescence : LifecycleEvidenceKind → Prop
  | .quiescenceWitness => True
  | .reclamationAdmission => True
  | .authoritativeHeadObservation => False
  | .retirementFence => False

def AuthorizesReclamation : LifecycleEvidenceKind → Prop
  | .reclamationAdmission => True
  | .authoritativeHeadObservation => False
  | .retirementFence => False
  | .quiescenceWitness => False

inductive NewUseEvidenceKind where
  | admittedBeforeFence
  | ordinaryUseAfterFence
  | authorizedMaintenanceAfterFence
  deriving DecidableEq, Repr

def AdmitsOrdinaryNewUse : NewUseEvidenceKind → Prop
  | .admittedBeforeFence => True
  | .ordinaryUseAfterFence => False
  | .authorizedMaintenanceAfterFence => False

theorem headObservationAloneDoesNotEstablishRetirement :
    ¬ EstablishesRetirement .authoritativeHeadObservation := by
  simp [EstablishesRetirement]

theorem retirementDoesNotEstablishQuiescence :
    ¬ EstablishesQuiescence .retirementFence := by
  simp [EstablishesQuiescence]

theorem quiescenceAloneDoesNotAuthorizeReclamation :
    ¬ AuthorizesReclamation .quiescenceWitness := by
  simp [AuthorizesReclamation]

theorem ordinaryNewUseAfterFenceFailsClosed :
    ¬ AdmitsOrdinaryNewUse .ordinaryUseAfterFence := by
  simp [AdmitsOrdinaryNewUse]

theorem retirementRequiresAuthoritativeHeadObservation
    {Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity : Type}
    (retirement :
      RetirementPrecondition
        Scope Generation Version AdapterProtocol ObservationReceipt
        FenceIdentity RetirementReceiptIdentity) :
    ∃ observation :
        ActiveHeadObservation
          Scope Generation Version AdapterProtocol ObservationReceipt,
      observation = retirement.activeHead := by
  exact ⟨retirement.activeHead, rfl⟩

theorem reclamationRequiresQuiescence
    {Scope Generation Version AdapterProtocol ObservationReceipt
      FenceIdentity RetirementReceiptIdentity
      PinIdentity ObligationIdentity QuiescenceReceiptIdentity
      Materialization Owner ReclamationReceiptIdentity : Type}
    (reclamation :
      ReclamationAdmission
        Scope Generation Version AdapterProtocol ObservationReceipt
        FenceIdentity RetirementReceiptIdentity
        PinIdentity ObligationIdentity QuiescenceReceiptIdentity
        Materialization Owner ReclamationReceiptIdentity) :
    ∃ witness :
        QuiescenceWitness
          Scope Generation Version AdapterProtocol ObservationReceipt
          FenceIdentity RetirementReceiptIdentity
          PinIdentity ObligationIdentity QuiescenceReceiptIdentity,
      witness = reclamation.quiescence := by
  exact ⟨reclamation.quiescence, rfl⟩


end PooFlowCoreProof.Admission.Publication.Retirement
