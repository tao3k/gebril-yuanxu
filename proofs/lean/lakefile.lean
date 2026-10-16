-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package PooFlowCoreProof where
  version := v!"0.1.0"

@[default_target]
lean_lib PooFlowModuleSystemProof where
  roots := #[
    `PooFlowCoreProof.PooC4.ActiveHeadPublication,
    `PooFlowCoreProof.PooC4.AdmissionFairnessIsolation,
    `PooFlowCoreProof.PooC4.CompositionIdentity,
    `PooFlowCoreProof.PooC4.CompositionReceipt,
    `PooFlowCoreProof.PooC4.ConservativeExtension,
    `PooFlowCoreProof.PooC4.ContinuationSuspensionBoundary,
    `PooFlowCoreProof.PooC4.ContributorRepositoryQualification,
    `PooFlowCoreProof.PooC4.ControlPolicyProfileProjection,
    `PooFlowCoreProof.PooC4.ControlPolicyResolution,
    `PooFlowCoreProof.PooC4.CrossDomainFederation,
    `PooFlowCoreProof.PooC4.DependencySourceIdentity,
    `PooFlowCoreProof.PooC4.DistributedCacheAdmission,
    `PooFlowCoreProof.PooC4.DistributedEvaluatorDelegation,
    `PooFlowCoreProof.PooC4.DomainCaseIndexedResolution,
    `PooFlowCoreProof.PooC4.EvaluationContextNarrowing,
    `PooFlowCoreProof.PooC4.EventIngressCausalCut,
    `PooFlowCoreProof.PooC4.EvidenceRetentionErasure,
    `PooFlowCoreProof.PooC4.ExplicitEntropyDerivation,
    `PooFlowCoreProof.PooC4.ExplicitRequirementResolution,
    `PooFlowCoreProof.PooC4.ExplicitTemporalObservations,
    `PooFlowCoreProof.PooC4.GenerationRetirementReclamation,
    `PooFlowCoreProof.PooC4.GerbilGambitRuntimeCorrespondence,
    `PooFlowCoreProof.PooC4.GerbilPooPhysicalRefinement,
    `PooFlowCoreProof.PooC4.GovernanceDecisionAuthority,
    `PooFlowCoreProof.PooC4.GovernedRolloutCohorts,
    `PooFlowCoreProof.PooC4.GraphCompatibilityClosure,
    `PooFlowCoreProof.PooC4.IncrementalFixedPointCacheCorrectness,
    `PooFlowCoreProof.PooC4.IncrementalTruthMaintenance,
    `PooFlowCoreProof.PooC4.MinimalUseCompositionSurface,
    `PooFlowCoreProof.PooC4.ModuleProfileBundleImports,
    `PooFlowCoreProof.PooC4.ModuleSemanticGraphSeparation,
    `PooFlowCoreProof.PooC4.MultiScopePublicationAtomicity,
    `PooFlowCoreProof.PooC4.NamespaceSeparation,
    `PooFlowCoreProof.PooC4.NativeProjectionPipeline,
    `PooFlowCoreProof.PooC4.NativeSemanticQueryModel,
    `PooFlowCoreProof.PooC4.ObservationSetConsistency,
    `PooFlowCoreProof.PooC4.OwnershipBoundaryLayers,
    `PooFlowCoreProof.PooC4.PersistentStateMigrationContract,
    `PooFlowCoreProof.PooC4.PhasedSlotResolution,
    `PooFlowCoreProof.PooC4.PooControlAlgebra,
    `PooFlowCoreProof.PooC4.PoofProofAdoption,
    `PooFlowCoreProof.PooC4.PrincipalKeyLifecycle,
    `PooFlowCoreProof.PooC4.ProfileBundleStableIdentity,
    `PooFlowCoreProof.PooC4.ProfilePrototypeCorrespondence,
    `PooFlowCoreProof.PooC4.ProfileRevisionUpgrade,
    `PooFlowCoreProof.PooC4.PublicationActivationCompletion,
    `PooFlowCoreProof.PooC4.RealizationAdmission,
    `PooFlowCoreProof.PooC4.ResourceConcurrencyControl,
    `PooFlowCoreProof.PooC4.ResultContractAccumulation,
    `PooFlowCoreProof.PooC4.ScaleParametricModuleGraph,
    `PooFlowCoreProof.PooC4.SlotDemandIdentity,
    `PooFlowCoreProof.PooC4.StrategyFacetPurity,
    `PooFlowCoreProof.PooC4.UseCompositionMacroContract
  ]
