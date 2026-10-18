-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Modules.Funflow.Policy

namespace PooFlowCoreProof.Modules.Funflow.ProfileProjection

inductive ProfileOperandKind where
  | profile
  | profileBundle
  | rawControlPolicy
  deriving DecidableEq, Repr

structure UserCompositionSurface where
  oneUserCompositionProjection : Prop
  singleProjectionEstablished : oneUserCompositionProjection
  bodyIsComposeProfiles : Prop
  composeBodyEstablished : bodyIsComposeProfiles
  everyOperandIsProfileValue : Prop
  operandClosureEstablished : everyOperandIsProfileValue
  nestedUserCompositionExists : Prop
  noNestedUserComposition : ¬ nestedUserCompositionExists
  nestedComposeExists : Prop
  noNestedCompose : ¬ nestedComposeExists
  controlPolicyClauseExists : Prop
  noControlPolicyClause : ¬ controlPolicyClauseExists
  thinHygienicModuleProjection : Prop
  thinProjectionEstablished : thinHygienicModuleProjection

structure OperandAdmission where
  profileAdmitted : Prop
  profileAdmissionEstablished : profileAdmitted
  profileBundleAdmitted : Prop
  profileBundleAdmissionEstablished : profileBundleAdmitted
  rawControlPolicyAdmitted : Prop
  rawPolicyRejected : ¬ rawControlPolicyAdmitted
  moduleSelectionProofRequired : Prop
  selectionProofEstablished : moduleSelectionProofRequired

structure CompositionCoreBoundary where
  composeIsPureFunction : Prop
  composePurityEstablished : composeIsPureFunction
  profilesIsPooStrategyObject : Prop
  profilesStrategyEstablished : profilesIsPooStrategyObject
  compositionExecutesPolicy : Prop
  noPolicyExecution : ¬ compositionExecutesPolicy
  compositionIssuesAuthority : Prop
  noAuthorityIssuance : ¬ compositionIssuesAuthority
  explicitRootInstantiationCount : Nat
  exactlyOneRootInstantiation : explicitRootInstantiationCount = 1

structure HigherOrderProfileProjection where
  preservesPolicyIdentity : Prop
  policyIdentityEstablished : preservesPolicyIdentity
  preservesPrototypeLineage : Prop
  lineageEstablished : preservesPrototypeLineage
  preservesImportsObject : Prop
  importsEstablished : preservesImportsObject
  preservesIdentityObject : Prop
  identityEstablished : preservesIdentityObject
  preservesCapabilityObject : Prop
  capabilityEstablished : preservesCapabilityObject
  preservesPriority : Prop
  priorityEstablished : preservesPriority
  preservesProfileProvenance : Prop
  provenanceEstablished : preservesProfileProvenance
  containsRuntimeAuthority : Prop
  noRuntimeAuthority : ¬ containsRuntimeAuthority
  containsLiveContinuation : Prop
  noLiveContinuation : ¬ containsLiveContinuation
  containsRuntimeHandler : Prop
  noRuntimeHandler : ¬ containsRuntimeHandler
  containsIssuerWitness : Prop
  noIssuerWitness : ¬ containsIssuerWitness
  returnsProfileValue : Prop
  noProfileResult : ¬ returnsProfileValue
  containsUnresolvedExternalEffect : Prop
  noUnresolvedExternalEffect : ¬ containsUnresolvedExternalEffect

structure PolicyCollectionLaw where
  immutableCollection : Prop
  immutabilityEstablished : immutableCollection
  hiddenRegistryExists : Prop
  noHiddenRegistry : ¬ hiddenRegistryExists
  keyedByStablePolicyIdentity : Prop
  stableKeyEstablished : keyedByStablePolicyIdentity
  canonicalEnumeration : Prop
  canonicalEnumerationEstablished : canonicalEnumeration
  distinctIdentitiesCoexist : Prop
  coexistenceEstablished : distinctIdentitiesCoexist
  identicalDuplicateIsIdempotent : Prop
  duplicateIdempotenceEstablished : identicalDuplicateIsIdempotent
  compatibleRefinementsCompose : Prop
  refinementCompositionEstablished : compatibleRefinementsCompose
  duplicateCapabilitiesIntersect : Prop
  capabilityIntersectionEstablished : duplicateCapabilitiesIntersect
  incompatibleDuplicateFailsClosed : Prop
  duplicateConflictClosureEstablished : incompatibleDuplicateFailsClosed
  priorityResolvesDuplicateDefinition : Prop
  noPriorityResolution : ¬ priorityResolvesDuplicateDefinition
  sourceOrderResolvesDuplicateDefinition : Prop
  noSourceOrderResolution : ¬ sourceOrderResolvesDuplicateDefinition

structure AuthorityBoundary where
  profilePresenceIssuesAuthority : Prop
  noPresenceAuthority : ¬ profilePresenceIssuesAuthority
  objectShapeIssuesAuthority : Prop
  noShapeAuthority : ¬ objectShapeIssuesAuthority
  evaluatorBoundaryIssuesAuthority : Prop
  evaluatorAuthorityEstablished : evaluatorBoundaryIssuesAuthority
  unavailablePolicyRemainsVisible : Prop
  rejectedPolicyVisibilityEstablished : unavailablePolicyRemainsVisible
  missingAuthorityHasActionableReceipt : Prop
  actionableReceiptEstablished : missingAuthorityHasActionableReceipt

structure ImportsProjectionBoundary where
  importsIdentityCapabilityAreDistinctObjects : Prop
  distinctObjectsEstablished : importsIdentityCapabilityAreDistinctObjects
  recursiveSubmoduleImportsPreserved : Prop
  recursiveImportsEstablished : recursiveSubmoduleImportsPreserved
  capabilityRequirementsIntersectOnEdges : Prop
  edgeIntersectionEstablished : capabilityRequirementsIntersectOnEdges
  cyclesPreservedForBoundedObservation : Prop
  cycleObservationEstablished : cyclesPreservedForBoundedObservation
  gerbilImportIsPublicInterface : Prop
  backendImportNotPublic : ¬ gerbilImportIsPublicInterface
  userEnumeratesTransitiveImports : Prop
  noUserImportEnumeration : ¬ userEnumeratesTransitiveImports

structure MacroBoundary where
  enumeratesPolicies : Prop
  noPolicyEnumeration : ¬ enumeratesPolicies
  resolvesPolicyPriority : Prop
  noPriorityResolution : ¬ resolvesPolicyPriority
  manufacturesCapability : Prop
  noCapabilityManufacture : ¬ manufacturesCapability
  installsRuntimeHandler : Prop
  noHandlerInstallation : ¬ installsRuntimeHandler
  introducesPolicyDsl : Prop
  noPolicyDsl : ¬ introducesPolicyDsl
  expandsToPooValuesAndPureComposition : Prop
  ordinaryExpansionEstablished : expandsToPooValuesAndPureComposition
  runtimeReentersExpansion : Prop
  noRuntimeReentry : ¬ runtimeReentersExpansion

structure CrossPlaneLaw where
  profileCompositionPure : Prop
  purityEstablished : profileCompositionPure
  runtimeRecomposesProfiles : Prop
  noRuntimeRecomposition : ¬ runtimeRecomposesProfiles
  policyReceiptEntersProfileDomain : Prop
  receiptOutsideProfileDomain : ¬ policyReceiptEntersProfileDomain
  erasurePreservesComposedProfile : Prop
  profileErasureEstablished : erasurePreservesComposedProfile
  erasurePreservesNativeOutcome : Prop
  nativeErasureEstablished : erasurePreservesNativeOutcome
  operandPermutationPreservesCollectionIdentity : Prop
  permutationEstablished : operandPermutationPreservesCollectionIdentity
  policyObservationForcesNativeSlot : Prop
  noAdditionalNativeForcing : ¬ policyObservationForcesNativeSlot

structure ProjectionAdmissionClosure where
  userCompositionSurfaceEstablished : Prop
  operandsAreProfilesOrProvenBundles : Prop
  higherOrderProjectionEstablished : Prop
  importsIdentityCapabilitySeparated : Prop
  immutableRegistryFreeCollection : Prop
  duplicateIdentityLawsEstablished : Prop
  presenceCannotIssueAuthority : Prop
  decisionPrioritySeparated : Prop
  macroBoundaryEstablished : Prop
  gerbilPooInterfaceVerified : Prop
  conservativeExtensionEstablished : Prop
  priorRfcObligationsSatisfied : Prop

def ImplementationAdmitted
    (closure : ProjectionAdmissionClosure) : Prop :=
  closure.userCompositionSurfaceEstablished ∧
    closure.operandsAreProfilesOrProvenBundles ∧
    closure.higherOrderProjectionEstablished ∧
    closure.importsIdentityCapabilitySeparated ∧
    closure.immutableRegistryFreeCollection ∧
    closure.duplicateIdentityLawsEstablished ∧
    closure.presenceCannotIssueAuthority ∧
    closure.decisionPrioritySeparated ∧
    closure.macroBoundaryEstablished ∧
    closure.gerbilPooInterfaceVerified ∧
    closure.conservativeExtensionEstablished ∧
    closure.priorRfcObligationsSatisfied

theorem projectionPreservesImportsIdentityAndCapability
    (projection : HigherOrderProfileProjection) :
    projection.preservesImportsObject ∧
      projection.preservesIdentityObject ∧
      projection.preservesCapabilityObject :=
  ⟨projection.importsEstablished, projection.identityEstablished,
    projection.capabilityEstablished⟩

theorem projectionPreservesPriorityAndProvenance
    (projection : HigherOrderProfileProjection) :
    projection.preservesPriority ∧ projection.preservesProfileProvenance :=
  ⟨projection.priorityEstablished, projection.provenanceEstablished⟩

theorem projectionContainsNoHandlerOrIssuerWitness
    (projection : HigherOrderProfileProjection) :
    ¬ projection.containsRuntimeHandler ∧
      ¬ projection.containsIssuerWitness :=
  ⟨projection.noRuntimeHandler, projection.noIssuerWitness⟩

theorem policyCollectionIsImmutableAndRegistryFree
    (law : PolicyCollectionLaw) :
    law.immutableCollection ∧ ¬ law.hiddenRegistryExists :=
  ⟨law.immutabilityEstablished, law.noHiddenRegistry⟩

theorem policyCollectionUsesStableIdentityAndCanonicalOrder
    (law : PolicyCollectionLaw) :
    law.keyedByStablePolicyIdentity ∧ law.canonicalEnumeration :=
  ⟨law.stableKeyEstablished, law.canonicalEnumerationEstablished⟩

theorem identicalDuplicateIsIdempotent
    (law : PolicyCollectionLaw) :
    law.identicalDuplicateIsIdempotent :=
  law.duplicateIdempotenceEstablished

theorem duplicateCapabilitiesIntersect
    (law : PolicyCollectionLaw) :
    law.duplicateCapabilitiesIntersect :=
  law.capabilityIntersectionEstablished

theorem incompatibleDuplicateFailsClosed
    (law : PolicyCollectionLaw) :
    law.incompatibleDuplicateFailsClosed :=
  law.duplicateConflictClosureEstablished

theorem profilePresenceAndShapeIssueNoAuthority
    (boundary : AuthorityBoundary) :
    ¬ boundary.profilePresenceIssuesAuthority ∧
      ¬ boundary.objectShapeIssuesAuthority :=
  ⟨boundary.noPresenceAuthority, boundary.noShapeAuthority⟩

theorem unavailablePolicyRemainsVisibleWithReceipt
    (boundary : AuthorityBoundary) :
    boundary.unavailablePolicyRemainsVisible ∧
      boundary.missingAuthorityHasActionableReceipt :=
  ⟨boundary.rejectedPolicyVisibilityEstablished,
    boundary.actionableReceiptEstablished⟩

theorem macroDoesNotEnumerateOrResolvePolicies
    (boundary : MacroBoundary) :
    ¬ boundary.enumeratesPolicies ∧ ¬ boundary.resolvesPolicyPriority :=
  ⟨boundary.noPolicyEnumeration, boundary.noPriorityResolution⟩

theorem macroInstallsNoRuntimeHandler
    (boundary : MacroBoundary) :
    ¬ boundary.installsRuntimeHandler :=
  boundary.noHandlerInstallation

theorem projectionErasurePreservesProfileAndNativeOutcome
    (law : CrossPlaneLaw) :
    law.erasurePreservesComposedProfile ∧ law.erasurePreservesNativeOutcome :=
  ⟨law.profileErasureEstablished, law.nativeErasureEstablished⟩

theorem operandPermutationPreservesCollectionIdentity
    (law : CrossPlaneLaw) :
    law.operandPermutationPreservesCollectionIdentity :=
  law.permutationEstablished

theorem implementationRequirements
    (closure : ProjectionAdmissionClosure)
    (admitted : ImplementationAdmitted closure) :
    closure.userCompositionSurfaceEstablished ∧
      closure.operandsAreProfilesOrProvenBundles ∧
      closure.higherOrderProjectionEstablished ∧
      closure.importsIdentityCapabilitySeparated ∧
      closure.immutableRegistryFreeCollection ∧
      closure.duplicateIdentityLawsEstablished ∧
      closure.presenceCannotIssueAuthority ∧
      closure.decisionPrioritySeparated ∧
      closure.macroBoundaryEstablished ∧
      closure.gerbilPooInterfaceVerified ∧
      closure.conservativeExtensionEstablished ∧
      closure.priorRfcObligationsSatisfied :=
  admitted

theorem missingUserCompositionSurfaceBlocksImplementation
    (closure : ProjectionAdmissionClosure)
    (missing : ¬ closure.userCompositionSurfaceEstablished) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing (implementationRequirements closure admitted).1

theorem missingAuthorityBoundaryBlocksImplementation
    (closure : ProjectionAdmissionClosure)
    (missing : ¬ closure.presenceCannotIssueAuthority) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing (implementationRequirements closure admitted).2.2.2.2.2.2.1

theorem unverifiedGerbilPooInterfaceBlocksImplementation
    (closure : ProjectionAdmissionClosure)
    (missing : ¬ closure.gerbilPooInterfaceVerified) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing
    (implementationRequirements closure admitted).2.2.2.2.2.2.2.2.2.1

end PooFlowCoreProof.Modules.Funflow.ProfileProjection
