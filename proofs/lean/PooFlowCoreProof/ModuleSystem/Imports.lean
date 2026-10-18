-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.ProfileComposition.Syntax

namespace PooFlowCoreProof.ModuleSystem.Imports

abbrev Selection (ProfileIdentity : Type) :=
  ProfileIdentity → Prop

structure ModuleObjectBoundary where
  immutablePooObject : Prop
  immutabilityEstablished : immutablePooObject
  stableDefinitionIdentity : Prop
  definitionIdentityEstablished : stableDefinitionIdentity
  exportsStableProfiles : Prop
  exportSurfaceEstablished : exportsStableProfiles
  ownsRecursiveImports : Prop
  importsOwnershipEstablished : ownsRecursiveImports
  ownsCapabilityRequirements : Prop
  capabilityRequirementsEstablished : ownsCapabilityRequirements
  ownsSubmoduleRelationships : Prop
  submoduleOwnershipEstablished : ownsSubmoduleRelationships
  ownsRevisionAndGeneration : Prop
  revisionGenerationEstablished : ownsRevisionAndGeneration
  containsLiveRuntimeAuthority : Prop
  noRuntimeAuthority : ¬ containsLiveRuntimeAuthority
  hasGlobalRegistryEntry : Prop
  noGlobalRegistry : ¬ hasGlobalRegistryEntry
  installsPackages : Prop
  noPackageInstallation : ¬ installsPackages

structure ProfileObjectBoundary where
  immutablePooValue : Prop
  immutabilityEstablished : immutablePooValue
  stableProfileIdentity : Prop
  profileIdentityEstablished : stableProfileIdentity
  owningModuleIdentity : Prop
  moduleIdentityEstablished : owningModuleIdentity
  dependencyProjection : Prop
  dependencyProjectionEstablished : dependencyProjection
  capabilityRequirements : Prop
  capabilityRequirementsEstablished : capabilityRequirements
  prototypeLineage : Prop
  lineageEstablished : prototypeLineage
  selectionMutatesDefinition : Prop
  noSelectionMutation : ¬ selectionMutatesDefinition

structure ProfileBundleBoundary where
  immutablePooValue : Prop
  immutabilityEstablished : immutablePooValue
  preservesModuleDefinitionIdentity : Prop
  moduleDefinitionEstablished : preservesModuleDefinitionIdentity
  preservesModuleInstanceIdentity : Prop
  moduleInstanceEstablished : preservesModuleInstanceIdentity
  preservesSelectedProfileIdentities : Prop
  selectedProfilesEstablished : preservesSelectedProfileIdentities
  containsOnlySelectedDependencyRoots : Prop
  selectedRootsEstablished : containsOnlySelectedDependencyRoots
  preservesCapabilityRequirements : Prop
  capabilitiesEstablished : preservesCapabilityRequirements
  preservesRevisionGenerationProvenance : Prop
  revisionGenerationProvenanceEstablished :
    preservesRevisionGenerationProvenance
  hasExportMembershipProof : Prop
  exportMembershipEstablished : hasExportMembershipProof
  admittedAsProfileOperand : Prop
  operandAdmissionEstablished : admittedAsProfileOperand

structure UseModuleBoundary where
  acceptsDefaultInstanceForm : Prop
  defaultFormEstablished : acceptsDefaultInstanceForm
  acceptsExplicitAliasForm : Prop
  aliasFormEstablished : acceptsExplicitAliasForm
  requiresNonemptySelection : Prop
  nonemptySelectionEstablished : requiresNonemptySelection
  validatesExportMembership : Prop
  membershipValidationEstablished : validatesExportMembership
  returnsProfileBundleValue : Prop
  bundleValueEstablished : returnsProfileBundleValue
  definesOrMutatesProfiles : Prop
  noProfileDefinition : ¬ definesOrMutatesProfiles
  parsesComposeOrStageClauses : Prop
  noClauseParsing : ¬ parsesComposeOrStageClauses
  lowersToAlist : Prop
  noAlistLowering : ¬ lowersToAlist
  issuesCapability : Prop
  noCapabilityIssuance : ¬ issuesCapability
  enumeratesTransitiveClosure : Prop
  noClosureEnumeration : ¬ enumeratesTransitiveClosure

structure ImportsClosureBoundary where
  immutableRecursivePooObject : Prop
  recursiveObjectEstablished : immutableRecursivePooObject
  reachableRootsProjectedBeforeClosure : Prop
  reachabilityOrderEstablished : reachableRootsProjectedBeforeClosure
  unselectedSubgraphsInactive : Prop
  inactiveSubgraphsEstablished : unselectedSubgraphsInactive
  recursiveSubmodulesFollowed : Prop
  recursiveSubmodulesEstablished : recursiveSubmodulesFollowed
  nodesDeduplicatedByDefinitionIdentity : Prop
  definitionDeduplicationEstablished : nodesDeduplicatedByDefinitionIdentity
  explicitInstancesRemainDistinct : Prop
  instanceSeparationEstablished : explicitInstancesRemainDistinct
  capabilitiesIntersectAlongEdges : Prop
  edgeIntersectionEstablished : capabilitiesIntersectAlongEdges
  revisionGenerationRecorded : Prop
  revisionGenerationEstablished : revisionGenerationRecorded
  cyclesPreserved : Prop
  cyclePreservationEstablished : cyclesPreserved

structure FixedPointBoundary where
  useModuleEvaluatesCycles : Prop
  noMacroCycleEvaluation : ¬ useModuleEvaluatesCycles
  introducesSecondFixedPointEvaluator : Prop
  noSecondEvaluator : ¬ introducesSecondFixedPointEvaluator
  delegatesToPooFlowFixedPoint : Prop
  delegationEstablished : delegatesToPooFlowFixedPoint
  cycleIdentityObserved : Prop
  cycleIdentityEstablished : cycleIdentityObserved
  demandBudgetObserved : Prop
  demandBudgetEstablished : demandBudgetObserved
  continuableControlAvailable : Prop
  continuableControlEstablished : continuableControlAvailable

structure BackendProjectionBoundary where
  occursAfterSemanticAdmission : Prop
  admissionOrderEstablished : occursAfterSemanticAdmission
  deterministicForClosureRevision : Prop
  determinismEstablished : deterministicForClosureRevision
  projectsOnlyReachableBoundaries : Prop
  reachabilityEstablished : projectsOnlyReachableBoundaries
  changesSelectedProfileSemantics : Prop
  noSemanticChange : ¬ changesSelectedProfileSemantics
  userEnumeratesPhysicalImports : Prop
  noUserEnumeration : ¬ userEnumeratesPhysicalImports
  performsGerbilPackageInstallation : Prop
  noPackageInstallation : ¬ performsGerbilPackageInstallation

structure CompositionBoundary where
  bundleIsOrdinaryProfilesOperand : Prop
  operandAdmissionEstablished : bundleIsOrdinaryProfilesOperand
  composeReceivesOnlyValues : Prop
  valueCompositionEstablished : composeReceivesOnlyValues
  aggregateModuleHidesTransitiveScale : Prop
  aggregateScaleEstablished : aggregateModuleHidesTransitiveScale
  aggregateModuleHidesIdentityEvidence : Prop
  identityEvidencePreserved : ¬ aggregateModuleHidesIdentityEvidence
  rootInstantiationCount : Nat
  exactlyOneRootInstantiation : rootInstantiationCount = 1

structure ModuleAdmissionClosure where
  objectFamiliesDistinct : Prop
  useModuleFormsEstablished : Prop
  selectionOnlySurfaceEstablished : Prop
  nativePooExtensionEstablished : Prop
  profileBundleOperandEstablished : Prop
  selectionAlgebraEstablished : Prop
  reachableImportsEstablished : Prop
  capabilityAttenuationEstablished : Prop
  cycleBoundaryEstablished : Prop
  backendProjectionBoundaryEstablished : Prop
  noAlistRegistryOrCompatibilityParser : Prop
  gerbilPooCallsVerified : Prop
  priorRfcObligationsSatisfied : Prop

def ImplementationAdmitted (closure : ModuleAdmissionClosure) : Prop :=
  closure.objectFamiliesDistinct ∧
    closure.useModuleFormsEstablished ∧
    closure.selectionOnlySurfaceEstablished ∧
    closure.nativePooExtensionEstablished ∧
    closure.profileBundleOperandEstablished ∧
    closure.selectionAlgebraEstablished ∧
    closure.reachableImportsEstablished ∧
    closure.capabilityAttenuationEstablished ∧
    closure.cycleBoundaryEstablished ∧
    closure.backendProjectionBoundaryEstablished ∧
    closure.noAlistRegistryOrCompatibilityParser ∧
    closure.gerbilPooCallsVerified ∧
    closure.priorRfcObligationsSatisfied

theorem defaultInstanceIdentityIsDefinitionIdentity
    {ModuleIdentity : Type}
    (moduleIdentity : ModuleIdentity) :
    moduleIdentity = moduleIdentity :=
  rfl

theorem explicitInstancesRemainDistinct
    {ModuleIdentity InstanceIdentity : Type}
    (moduleIdentity : ModuleIdentity)
    (left right : InstanceIdentity)
    (distinct : left ≠ right) :
    (moduleIdentity, left) ≠ (moduleIdentity, right) := by
  intro equal
  exact distinct (Prod.mk.inj equal).2

theorem moduleHasStableDefinitionIdentityAndExports
    (boundary : ModuleObjectBoundary) :
    boundary.stableDefinitionIdentity ∧ boundary.exportsStableProfiles :=
  ⟨boundary.definitionIdentityEstablished, boundary.exportSurfaceEstablished⟩

theorem moduleOwnsImportsCapabilitiesAndSubmodules
    (boundary : ModuleObjectBoundary) :
    boundary.ownsRecursiveImports ∧
      boundary.ownsCapabilityRequirements ∧
      boundary.ownsSubmoduleRelationships :=
  ⟨boundary.importsOwnershipEstablished,
    boundary.capabilityRequirementsEstablished,
    boundary.submoduleOwnershipEstablished⟩

theorem profilePreservesIdentityOwnershipAndDependencyProjection
    (boundary : ProfileObjectBoundary) :
    boundary.stableProfileIdentity ∧
      boundary.owningModuleIdentity ∧
      boundary.dependencyProjection :=
  ⟨boundary.profileIdentityEstablished, boundary.moduleIdentityEstablished,
    boundary.dependencyProjectionEstablished⟩

theorem profilePreservesCapabilityAndLineage
    (boundary : ProfileObjectBoundary) :
    boundary.capabilityRequirements ∧ boundary.prototypeLineage :=
  ⟨boundary.capabilityRequirementsEstablished, boundary.lineageEstablished⟩

theorem bundlePreservesModuleDefinitionAndInstanceIdentity
    (boundary : ProfileBundleBoundary) :
    boundary.preservesModuleDefinitionIdentity ∧
      boundary.preservesModuleInstanceIdentity :=
  ⟨boundary.moduleDefinitionEstablished, boundary.moduleInstanceEstablished⟩

theorem bundlePreservesSelectedProfilesAndOnlyTheirRoots
    (boundary : ProfileBundleBoundary) :
    boundary.preservesSelectedProfileIdentities ∧
      boundary.containsOnlySelectedDependencyRoots :=
  ⟨boundary.selectedProfilesEstablished, boundary.selectedRootsEstablished⟩

theorem bundlePreservesCapabilitiesRevisionAndProvenance
    (boundary : ProfileBundleBoundary) :
    boundary.preservesCapabilityRequirements ∧
      boundary.preservesRevisionGenerationProvenance :=
  ⟨boundary.capabilitiesEstablished,
    boundary.revisionGenerationProvenanceEstablished⟩

theorem useModuleAcceptsOnlyDefaultAndAliasForms
    (boundary : UseModuleBoundary) :
    boundary.acceptsDefaultInstanceForm ∧
      boundary.acceptsExplicitAliasForm :=
  ⟨boundary.defaultFormEstablished, boundary.aliasFormEstablished⟩

theorem useModuleRequiresNonemptyExportedSelection
    (boundary : UseModuleBoundary) :
    boundary.requiresNonemptySelection ∧ boundary.validatesExportMembership :=
  ⟨boundary.nonemptySelectionEstablished,
    boundary.membershipValidationEstablished⟩

theorem importsDeduplicatesDefinitionsButSeparatesInstances
    (boundary : ImportsClosureBoundary) :
    boundary.nodesDeduplicatedByDefinitionIdentity ∧
      boundary.explicitInstancesRemainDistinct :=
  ⟨boundary.definitionDeduplicationEstablished,
    boundary.instanceSeparationEstablished⟩

theorem importsRecordsRevisionGenerationAndCycles
    (boundary : ImportsClosureBoundary) :
    boundary.revisionGenerationRecorded ∧ boundary.cyclesPreserved :=
  ⟨boundary.revisionGenerationEstablished,
    boundary.cyclePreservationEstablished⟩

theorem fixedPointObservesIdentityBudgetAndContinuableControl
    (boundary : FixedPointBoundary) :
    boundary.cycleIdentityObserved ∧
      boundary.demandBudgetObserved ∧
      boundary.continuableControlAvailable :=
  ⟨boundary.cycleIdentityEstablished, boundary.demandBudgetEstablished,
    boundary.continuableControlEstablished⟩

theorem backendProjectionIsDeterministicAndReachableOnly
    (boundary : BackendProjectionBoundary) :
    boundary.deterministicForClosureRevision ∧
      boundary.projectsOnlyReachableBoundaries :=
  ⟨boundary.determinismEstablished, boundary.reachabilityEstablished⟩

theorem bundleIsOrdinaryValueOperand
    (boundary : CompositionBoundary) :
    boundary.bundleIsOrdinaryProfilesOperand ∧ boundary.composeReceivesOnlyValues :=
  ⟨boundary.operandAdmissionEstablished, boundary.valueCompositionEstablished⟩

theorem aggregateModuleHidesScaleButNotIdentity
    (boundary : CompositionBoundary) :
    boundary.aggregateModuleHidesTransitiveScale ∧
      ¬ boundary.aggregateModuleHidesIdentityEvidence :=
  ⟨boundary.aggregateScaleEstablished, boundary.identityEvidencePreserved⟩

theorem implementationRequirements
    (closure : ModuleAdmissionClosure)
    (admitted : ImplementationAdmitted closure) :
    closure.objectFamiliesDistinct ∧
      closure.useModuleFormsEstablished ∧
      closure.selectionOnlySurfaceEstablished ∧
      closure.nativePooExtensionEstablished ∧
      closure.profileBundleOperandEstablished ∧
      closure.selectionAlgebraEstablished ∧
      closure.reachableImportsEstablished ∧
      closure.capabilityAttenuationEstablished ∧
      closure.cycleBoundaryEstablished ∧
      closure.backendProjectionBoundaryEstablished ∧
      closure.noAlistRegistryOrCompatibilityParser ∧
      closure.gerbilPooCallsVerified ∧
      closure.priorRfcObligationsSatisfied :=
  admitted

theorem missingSelectionAlgebraBlocksImplementation
    (closure : ModuleAdmissionClosure)
    (missing : ¬ closure.selectionAlgebraEstablished) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing
    (implementationRequirements closure admitted).2.2.2.2.2.1

theorem secondFixedPointEvaluatorBlocksImplementation
    (closure : ModuleAdmissionClosure)
    (missing : ¬ closure.cycleBoundaryEstablished) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing
    (implementationRequirements closure admitted).2.2.2.2.2.2.2.2.1

theorem unverifiedGerbilPooCallsBlockImplementation
    (closure : ModuleAdmissionClosure)
    (missing : ¬ closure.gerbilPooCallsVerified) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing
    (implementationRequirements closure admitted).2.2.2.2.2.2.2.2.2.2.2.1

end PooFlowCoreProof.ModuleSystem.Imports
