-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Modules.Funflow.ProfileProjection

namespace PooFlowCoreProof.ProfileComposition.Syntax

structure CurrentMacroGap where
  parsesDedicatedModuleForm : Prop
  dedicatedModuleParsingObserved : parsesDedicatedModuleForm
  parsesClauseSequence : Prop
  clauseParsingObserved : parsesClauseSequence
  returnsExpressionWithoutNamedBinding : Prop
  missingBindingObserved : returnsExpressionWithoutNamedBinding
  requiresDuplicateOuterDefinition : Prop
  duplicateDefinitionObserved : requiresDuplicateOuterDefinition
  composeIsClauseTransformer : Prop
  clauseComposeObserved : composeIsClauseTransformer
  profilesIsClauseTransformer : Prop
  clauseProfilesObserved : profilesIsClauseTransformer
  usesAlistLowering : Prop
  alistLoweringObserved : usesAlistLowering
  implementationAndDocumentationDisagree : Prop
  disagreementObserved : implementationAndDocumentationDisagree
  verifiedDefprofileImplementationExists : Prop
  noVerifiedDefprofile : ¬ verifiedDefprofileImplementationExists

structure TargetMacroShape where
  operandCountAfterMacroName : Nat
  exactlyTwoOperands : operandCountAfterMacroName = 2
  compositionNameIsIdentifier : Prop
  identifierEstablished : compositionNameIsIdentifier
  compositionExpressionPreserved : Prop
  expressionPreservationEstablished : compositionExpressionPreserved
  moduleLevelBindingCount : Nat
  exactlyOneBinding : moduleLevelBindingCount = 1
  enclosingDefinitionRequired : Prop
  noEnclosingDefinition : ¬ enclosingDefinitionRequired
  stableIdentityProjected : Prop
  identityProjectionEstablished : stableIdentityProjected
  rootInstantiationCount : Nat
  exactlyOneRootInstantiation : rootInstantiationCount = 1

structure HygieneContract where
  lexicalReferencesPreserved : Prop
  lexicalPreservationEstablished : lexicalReferencesPreserved
  importedBindingIdentitiesPreserved : Prop
  importedIdentitiesEstablished : importedBindingIdentitiesPreserved
  sourceLocationsPreserved : Prop
  sourceLocationsEstablished : sourceLocationsPreserved
  privateTemporaryCaptureOccurs : Prop
  noTemporaryCapture : ¬ privateTemporaryCaptureOccurs
  expressionConvertedToDatum : Prop
  noDatumConversion : ¬ expressionConvertedToDatum
  textualIdentifierDispatchOccurs : Prop
  noTextualDispatch : ¬ textualIdentifierDispatchOccurs
  importRenamingMutatesStableIdentity : Prop
  identityIndependentOfImportRename : ¬ importRenamingMutatesStableIdentity

structure ThinMacroBoundary where
  parsesComposeBody : Prop
  noComposeParsing : ¬ parsesComposeBody
  enumeratesOperands : Prop
  noOperandEnumeration : ¬ enumeratesOperands
  expandsProfileClauses : Prop
  noProfileClauseExpansion : ¬ expandsProfileClauses
  resolvesModuleAliases : Prop
  noAliasResolution : ¬ resolvesModuleAliases
  constructsAlist : Prop
  noAlistConstruction : ¬ constructsAlist
  callsObjectFromAlist : Prop
  noObjectFromAlist : ¬ callsObjectFromAlist
  manufacturesHooks : Prop
  noHookManufacture : ¬ manufacturesHooks
  inspectsPolicies : Prop
  noPolicyInspection : ¬ inspectsPolicies
  issuesCapabilities : Prop
  noCapabilityIssuance : ¬ issuesCapabilities
  installsRuntimeHandler : Prop
  noHandlerInstallation : ¬ installsRuntimeHandler
  evaluatesProfileDuringExpansion : Prop
  noExpansionEvaluation : ¬ evaluatesProfileDuringExpansion

structure ValueLevelBoundary where
  composeIsPureFunction : Prop
  composePurityEstablished : composeIsPureFunction
  profilesIsPooStrategy : Prop
  profilesStrategyEstablished : profilesIsPooStrategy
  useModuleIsIndependentValueProjection : Prop
  independentUseModuleEstablished : useModuleIsIndependentValueProjection
  profileBundlePreservesImportsIdentityCapability : Prop
  bundleProjectionEstablished : profileBundlePreservesImportsIdentityCapability
  recursiveImportsResolvedOutsideMacro : Prop
  importsPhaseEstablished : recursiveImportsResolvedOutsideMacro
  onlyAdmittedBackendImportsProjected : Prop
  backendProjectionEstablished : onlyAdmittedBackendImportsProjected

structure PhaseBoundary where
  expansionOwnsOnlyStructureAndIdentity : Prop
  expansionBoundaryEstablished : expansionOwnsOnlyStructureAndIdentity
  valueInitializationEvaluatesExpression : Prop
  valuePhaseEstablished : valueInitializationEvaluatesExpression
  rootOwnsSinglePooInstantiation : Prop
  rootBoundaryEstablished : rootOwnsSinglePooInstantiation
  runtimeReentersMacroExpansion : Prop
  noRuntimeReentry : ¬ runtimeReentersMacroExpansion
  macroPerformsPackageDiscovery : Prop
  noPackageDiscovery : ¬ macroPerformsPackageDiscovery

structure DirectReplacementBoundary where
  oldGrammarAccepted : Prop
  oldGrammarRejected : ¬ oldGrammarAccepted
  legacyParserFallbackExists : Prop
  noLegacyFallback : ¬ legacyParserFallbackExists
  syntaxVersionTokenExists : Prop
  noSyntaxVersionToken : ¬ syntaxVersionTokenExists
  deprecationPeriodExists : Prop
  noDeprecationPeriod : ¬ deprecationPeriodExists
  automaticSourceRewriteExists : Prop
  noAutomaticRewrite : ¬ automaticSourceRewriteExists
  runtimeCompatibilityAdapterExists : Prop
  noRuntimeCompatibilityAdapter : ¬ runtimeCompatibilityAdapterExists

structure ErrorBoundary where
  invalidArityIsMacroError : Prop
  arityErrorEstablished : invalidArityIsMacroError
  nonIdentifierIsMacroError : Prop
  identifierErrorEstablished : nonIdentifierIsMacroError
  identityOrRootProjectionFailureIsMacroBoundaryError : Prop
  projectionErrorEstablished : identityOrRootProjectionFailureIsMacroBoundaryError
  expressionErrorsPreserveOwnerAndLocation : Prop
  expressionErrorOwnershipEstablished : expressionErrorsPreserveOwnerAndLocation
  semanticFailureCollapsedToClauseParserError : Prop
  noSemanticErrorCollapse : ¬ semanticFailureCollapsedToClauseParserError

structure MacroAdmissionClosure where
  targetNameIsUseComposition : Prop
  twoOperandShapeEstablished : Prop
  singleBindingEstablished : Prop
  identityProjectionPooNative : Prop
  composeAndProfilesAreValues : Prop
  importsBoundaryEstablished : Prop
  clauseParserRemovedFromPublicPath : Prop
  noCompatibilitySurface : Prop
  hygieneEstablished : Prop
  phaseBoundaryEstablished : Prop
  userInterfaceCasesAligned : Prop
  gerbilPooCallsVerified : Prop
  priorRfcObligationsSatisfied : Prop

def ImplementationAdmitted (closure : MacroAdmissionClosure) : Prop :=
  closure.targetNameIsUseComposition ∧
    closure.twoOperandShapeEstablished ∧
    closure.singleBindingEstablished ∧
    closure.identityProjectionPooNative ∧
    closure.composeAndProfilesAreValues ∧
    closure.importsBoundaryEstablished ∧
    closure.clauseParserRemovedFromPublicPath ∧
    closure.noCompatibilitySurface ∧
    closure.hygieneEstablished ∧
    closure.phaseBoundaryEstablished ∧
    closure.userInterfaceCasesAligned ∧
    closure.gerbilPooCallsVerified ∧
    closure.priorRfcObligationsSatisfied

theorem currentComposeAndProfilesAreClauseTransformers
    (gap : CurrentMacroGap) :
    gap.composeIsClauseTransformer ∧ gap.profilesIsClauseTransformer :=
  ⟨gap.clauseComposeObserved, gap.clauseProfilesObserved⟩

theorem macroInstallsNoRuntimeHandler
    (boundary : ThinMacroBoundary) :
    ¬ boundary.installsRuntimeHandler :=
  boundary.noHandlerInstallation

theorem composeAndProfilesRemainValueLevelAbstractions
    (boundary : ValueLevelBoundary) :
    boundary.composeIsPureFunction ∧ boundary.profilesIsPooStrategy :=
  ⟨boundary.composePurityEstablished, boundary.profilesStrategyEstablished⟩

theorem profileBundlePreservesImportsIdentityCapability
    (boundary : ValueLevelBoundary) :
    boundary.profileBundlePreservesImportsIdentityCapability :=
  boundary.bundleProjectionEstablished

theorem expansionOwnsOnlyStructureAndIdentity
    (boundary : PhaseBoundary) :
    boundary.expansionOwnsOnlyStructureAndIdentity :=
  boundary.expansionBoundaryEstablished

theorem rootOwnsSinglePooInstantiation
    (boundary : PhaseBoundary) :
    boundary.rootOwnsSinglePooInstantiation :=
  boundary.rootBoundaryEstablished

theorem implementationRequirements
    (closure : MacroAdmissionClosure)
    (admitted : ImplementationAdmitted closure) :
    closure.targetNameIsUseComposition ∧
      closure.twoOperandShapeEstablished ∧
      closure.singleBindingEstablished ∧
      closure.identityProjectionPooNative ∧
      closure.composeAndProfilesAreValues ∧
      closure.importsBoundaryEstablished ∧
      closure.clauseParserRemovedFromPublicPath ∧
      closure.noCompatibilitySurface ∧
      closure.hygieneEstablished ∧
      closure.phaseBoundaryEstablished ∧
      closure.userInterfaceCasesAligned ∧
      closure.gerbilPooCallsVerified ∧
      closure.priorRfcObligationsSatisfied :=
  admitted

theorem wrongTargetMacroNameBlocksImplementation
    (closure : MacroAdmissionClosure)
    (missing : ¬ closure.targetNameIsUseComposition) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing (implementationRequirements closure admitted).1

theorem compatibilitySurfaceBlocksImplementation
    (closure : MacroAdmissionClosure)
    (invalid : ¬ closure.noCompatibilitySurface) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact invalid
    (implementationRequirements closure admitted).2.2.2.2.2.2.2.1

theorem unverifiedGerbilPooCallsBlockImplementation
    (closure : MacroAdmissionClosure)
    (missing : ¬ closure.gerbilPooCallsVerified) :
    ¬ ImplementationAdmitted closure := by
  intro admitted
  exact missing
    (implementationRequirements closure admitted).2.2.2.2.2.2.2.2.2.2.2.1

end PooFlowCoreProof.ProfileComposition.Syntax
