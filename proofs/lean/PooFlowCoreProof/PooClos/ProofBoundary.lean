-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.ProfileComposition.Prototype

namespace PooFlowCoreProof.PooClos.ProofBoundary

inductive SemanticAuthority where
  | poofTheory
  | gerbilPooImplementation
  | pooFlowProjection
  deriving DecidableEq, Repr

inductive CorrespondenceClass where
  | directPrototype
  | representationRefinement
  | wholeObjectRefinement
  | dependencyDelegation
  deriving DecidableEq, Repr

inductive QualificationOutcome where
  | operationalFailure
  | incompleteCorrespondence
  | profileAdmissionFailure
  deriving DecidableEq, Repr

structure UpstreamAdoptionBoundary where
  poofOwnsTheory : Prop
  poofTheoryAuthority : poofOwnsTheory
  gerbilPooOwnsImplementation : Prop
  gerbilPooImplementationAuthority : gerbilPooOwnsImplementation
  pooFlowOwnsProjectionOnly : Prop
  pooFlowProjectionAuthority : pooFlowOwnsProjectionOnly
  locallyReprovesPoofAlgebra : Prop
  noLocalPoofReproof : ¬ locallyReprovesPoofAlgebra
  createsSecondPooImplementation : Prop
  noSecondPooImplementation : ¬ createsSecondPooImplementation

structure CorrespondenceClassification where
  prototypePrimitives : CorrespondenceClass
  prototypeClassification :
    prototypePrimitives = .directPrototype
  slotSpecifications : CorrespondenceClass
  slotClassification :
    slotSpecifications = .representationRefinement
  wholeObjectConstruction : CorrespondenceClass
  objectClassification :
    wholeObjectConstruction = .wholeObjectRefinement
  c3Linearization : CorrespondenceClass
  c3Classification :
    c3Linearization = .dependencyDelegation

structure CorrespondenceReceipt where
  poofIdentityPinned : Prop
  poofPinEstablished : poofIdentityPinned
  gerbilPooIdentityPinned : Prop
  gerbilPooPinEstablished : gerbilPooIdentityPinned
  resolvedGerbilUtilsIdentityRecorded : Prop
  fourClassificationsVerified : Prop

def CorrespondenceClaimComplete
    (receipt : CorrespondenceReceipt) : Prop :=
  receipt.poofIdentityPinned ∧
    receipt.gerbilPooIdentityPinned ∧
    receipt.resolvedGerbilUtilsIdentityRecorded ∧
    receipt.fourClassificationsVerified

structure MissingRacketBoundary where
  executableReceiptRefreshed : Prop
  noExecutableRefresh : ¬ executableReceiptRefreshed
  invalidatesPublishedTheory : Prop
  theoryRemainsValid : ¬ invalidatesPublishedTheory
  countsAsUpstreamTestFailure : Prop
  notATestFailure : ¬ countsAsUpstreamTestFailure
  makesRacketRuntimeDependency : Prop
  noRacketRuntimeDependency : ¬ makesRacketRuntimeDependency

structure ProfileProjectionBoundary where
  domainSlotsRemainPooValues : Prop
  pooValueProjectionEstablished : domainSlotsRemainPooValues
  usesRawAlistDsl : Prop
  noRawAlistDsl : ¬ usesRawAlistDsl
  usesSymbolicOperandKind : Prop
  noSymbolicOperandKind : ¬ usesSymbolicOperandKind
  searchesFilesystemOrPackages : Prop
  noFilesystemOrPackageSearch : ¬ searchesFilesystemOrPackages
  readsGlobalProviderRegistry : Prop
  noGlobalProviderRegistry : ¬ readsGlobalProviderRegistry
  createsSecondObjectModel : Prop
  noSecondObjectModel : ¬ createsSecondObjectModel
  preservesDeclaredOperandOrder : Prop
  operandOrderEstablished : preservesDeclaredOperandOrder
  rootInstantiationCount : Nat
  oneNativeRoot : rootInstantiationCount = 1
  preservesNativeStructuralFailure : Prop
  nativeFailurePreservationEstablished : preservesNativeStructuralFailure

structure ConformanceWitnessBoundary where
  demonstratesPinnedIntegration : Prop
  integrationWitnessEstablished : demonstratesPinnedIntegration
  reprovesGeneralPoofTheory : Prop
  noReplacementProof : ¬ reprovesGeneralPoofTheory

structure ConservativeExtensionDelegation where
  ownedByRfc4586 : Prop
  delegationEstablished : ownedByRfc4586
  redefinedByProofAdoptionRfc : Prop
  noLocalRedefinition : ¬ redefinedByProofAdoptionRfc

theorem semanticAuthoritiesAreDistinct :
    SemanticAuthority.poofTheory ≠ .gerbilPooImplementation ∧
      SemanticAuthority.gerbilPooImplementation ≠ .pooFlowProjection ∧
      SemanticAuthority.poofTheory ≠ .pooFlowProjection := by
  decide

theorem poofOwnsTheory
    (boundary : UpstreamAdoptionBoundary) :
    boundary.poofOwnsTheory :=
  boundary.poofTheoryAuthority

theorem gerbilPooOwnsImplementation
    (boundary : UpstreamAdoptionBoundary) :
    boundary.gerbilPooOwnsImplementation :=
  boundary.gerbilPooImplementationAuthority

theorem pooFlowOwnsProjectionOnly
    (boundary : UpstreamAdoptionBoundary) :
    boundary.pooFlowOwnsProjectionOnly :=
  boundary.pooFlowProjectionAuthority

theorem missingDelegatedIdentityKeepsClaimIncomplete
    (receipt : CorrespondenceReceipt)
    (missing : ¬ receipt.resolvedGerbilUtilsIdentityRecorded) :
    ¬ CorrespondenceClaimComplete receipt := by
  intro complete
  exact missing complete.2.2.1

theorem unverifiedClassificationsKeepClaimIncomplete
    (receipt : CorrespondenceReceipt)
    (unverified : ¬ receipt.fourClassificationsVerified) :
    ¬ CorrespondenceClaimComplete receipt := by
  intro complete
  exact unverified complete.2.2.2

theorem qualificationOutcomesRemainDistinct :
    QualificationOutcome.operationalFailure ≠ .incompleteCorrespondence ∧
      QualificationOutcome.incompleteCorrespondence ≠ .profileAdmissionFailure ∧
      QualificationOutcome.operationalFailure ≠ .profileAdmissionFailure := by
  decide


end PooFlowCoreProof.PooClos.ProofBoundary
