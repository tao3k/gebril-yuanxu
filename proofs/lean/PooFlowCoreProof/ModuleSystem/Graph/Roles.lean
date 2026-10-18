-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.ModuleSystem.Source.Namespaces

namespace PooFlowCoreProof.ModuleSystem.Graph.Roles

inductive GraphRole where
  | gerbilModuleImport
  | pooSemanticDefinition
  deriving DecidableEq, Repr

def SupportsLazySemanticFixedPoint : GraphRole → Prop
  | .pooSemanticDefinition => True
  | .gerbilModuleImport => False

inductive GraphEdgeRole where
  | gerbilModuleImportEdge
  | profileSemanticRequirementEdge
  deriving DecidableEq, Repr

def IsLexicalCodeDependency : GraphEdgeRole → Prop
  | .gerbilModuleImportEdge => True
  | .profileSemanticRequirementEdge => False

def IsSemanticRequirement : GraphEdgeRole → Prop
  | .profileSemanticRequirementEdge => True
  | .gerbilModuleImportEdge => False

structure GerbilModuleGraph
    (GraphIdentity ModuleIdentity EdgeIdentity PhaseIdentity : Type) where
  graphIdentity : GraphIdentity
  modules : List ModuleIdentity
  importEdges : List EdgeIdentity
  phases : List PhaseIdentity
  ownsExpansionAndLoading : Prop
  ownershipEstablished : ownsExpansionAndLoading

structure PooSemanticGraph
    (GraphIdentity ProfileIdentity EdgeIdentity ComponentIdentity : Type) where
  graphIdentity : GraphIdentity
  profiles : List ProfileIdentity
  semanticEdges : List EdgeIdentity
  stronglyConnectedComponents : List ComponentIdentity
  ownsSemanticFixedPoint : Prop
  ownershipEstablished : ownsSemanticFixedPoint

structure SemanticGraphConstructionReceipt
    (ModuleGraphIdentity SemanticGraphIdentity ReceiptIdentity : Type) where
  moduleGraphIdentity : ModuleGraphIdentity
  semanticGraphIdentity : SemanticGraphIdentity
  requiredModulesLoaded : Prop
  modulesLoadedEstablished : requiredModulesLoaded
  composeProfilesInvoked : Prop
  composeInvocationEstablished : composeProfilesInvoked
  receiptIdentity : ReceiptIdentity

structure CrossProfileDependencyBoundary
    (ModuleEdgeIdentity SemanticEdgeIdentity : Type) where
  moduleImportEdgeIdentity : ModuleEdgeIdentity
  semanticRequirementEdgeIdentity : SemanticEdgeIdentity
  moduleImportCreatesSemanticRequirement : Prop
  noImplicitSemanticRequirement :
    ¬ moduleImportCreatesSemanticRequirement
  semanticRequirementCreatesModuleImport : Prop
  noImplicitModuleImport :
    ¬ semanticRequirementCreatesModuleImport

structure ModuleSystemOwnershipBoundary where
  pooFlowLoadsGerbilModules : Prop
  pooFlowOwnsMacroPhases : Prop
  pooFlowResolvesCircularModuleInitialization : Prop
  ownershipBoundary :
    ¬ pooFlowLoadsGerbilModules ∧
      ¬ pooFlowOwnsMacroPhases ∧
      ¬ pooFlowResolvesCircularModuleInitialization

inductive GraphFailureKind where
  | missingModuleImport
  | macroPhaseFailure
  | circularModuleInitialization
  | missingSemanticRequirement
  | capabilityRequirementFailure
  | semanticFixedPointDivergence
  deriving DecidableEq, Repr

def OwnedByGerbilModuleGraph : GraphFailureKind → Prop
  | .missingModuleImport => True
  | .macroPhaseFailure => True
  | .circularModuleInitialization => True
  | .missingSemanticRequirement => False
  | .capabilityRequirementFailure => False
  | .semanticFixedPointDivergence => False

def OwnedByPooSemanticGraph : GraphFailureKind → Prop
  | .missingModuleImport => False
  | .macroPhaseFailure => False
  | .circularModuleInitialization => False
  | .missingSemanticRequirement => True
  | .capabilityRequirementFailure => True
  | .semanticFixedPointDivergence => True

structure DistinctGraphIdentities
    (ModuleGraphIdentity SemanticGraphIdentity : Type) where
  moduleGraphIdentity : ModuleGraphIdentity
  semanticGraphIdentity : SemanticGraphIdentity
  identitiesConflated : Prop
  identitiesSeparated : ¬ identitiesConflated

theorem moduleGraphDoesNotSupportLazySemanticFixedPoint :
    ¬ SupportsLazySemanticFixedPoint .gerbilModuleImport := by
  simp [SupportsLazySemanticFixedPoint]

theorem semanticGraphSupportsLazyFixedPoint :
    SupportsLazySemanticFixedPoint .pooSemanticDefinition := by
  simp [SupportsLazySemanticFixedPoint]

theorem moduleImportEdgeIsLexicalDependency :
    IsLexicalCodeDependency .gerbilModuleImportEdge := by
  simp [IsLexicalCodeDependency]

theorem semanticRequirementEdgeIsNotLexicalDependency :
    ¬ IsLexicalCodeDependency .profileSemanticRequirementEdge := by
  simp [IsLexicalCodeDependency]

theorem semanticRequirementEdgeIsSemantic :
    IsSemanticRequirement .profileSemanticRequirementEdge := by
  simp [IsSemanticRequirement]

theorem moduleImportEdgeIsNotSemanticRequirement :
    ¬ IsSemanticRequirement .gerbilModuleImportEdge := by
  simp [IsSemanticRequirement]

theorem circularModuleFailureBelongsToGerbilGraph :
    OwnedByGerbilModuleGraph .circularModuleInitialization := by
  simp [OwnedByGerbilModuleGraph]

theorem semanticDivergenceBelongsToPooGraph :
    OwnedByPooSemanticGraph .semanticFixedPointDivergence := by
  simp [OwnedByPooSemanticGraph]

end PooFlowCoreProof.ModuleSystem.Graph.Roles
