-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import PooFlowCoreProof.Admission.Federation

namespace PooFlowCoreProof.ProfileComposition.Composition

inductive PublicCompositionSyntaxKind where
  | flatUseComposition
  | nestedUseComposition
  | clauseDsl
  deriving DecidableEq, Repr

def AdmitsPublicCompositionSyntax :
    PublicCompositionSyntaxKind → Prop
  | .flatUseComposition => True
  | .nestedUseComposition => False
  | .clauseDsl => False

structure HygienicUseComposition
    (Expression RootBinding ProvenanceIdentity : Type) where
  expression : Expression
  rootBinding : RootBinding
  provenanceIdentity : ProvenanceIdentity
  evaluationCount : Nat
  evaluatesExactlyOnce : evaluationCount = 1
  hygienicBinding : Prop
  hygieneEstablished : hygienicBinding

structure ComposeContract
    (Strategy Profile CompositionRoot : Type) where
  strategy : Strategy
  profiles : List Profile
  compositionRoot : CompositionRoot
  pureFunction : Prop
  purityEstablished : pureFunction
  canonicalRoot : Prop
  canonicalityEstablished : canonicalRoot
  readsHiddenRegistry : Prop
  noHiddenRegistry : ¬ readsHiddenRegistry
  executesEffects : Prop
  noEffectExecution : ¬ executesEffects
  parsesClauseDsl : Prop
  noClauseDsl : ¬ parsesClauseDsl

structure UseCompositionBoundary where
  evaluatesFixedPoint : Prop
  registersProviders : Prop
  selectsRuntimeAdapters : Prop
  executesEffects : Prop
  buildsHiddenRegistry : Prop
  createsSecondObjectSystem : Prop
  boundaryEstablished :
    ¬ evaluatesFixedPoint ∧
      ¬ registersProviders ∧
      ¬ selectsRuntimeAdapters ∧
      ¬ executesEffects ∧
      ¬ buildsHiddenRegistry ∧
      ¬ createsSecondObjectSystem

structure PackageAuthorProfile
    (ProfileIdentity PrototypeIdentity ImportIdentity
      CapabilityRequirementIdentity GraphIdentity : Type) where
  profileIdentity : ProfileIdentity
  prototypeIdentity : PrototypeIdentity
  importIdentity : ImportIdentity
  capabilityRequirementIdentity : CapabilityRequirementIdentity
  graphIdentity : GraphIdentity
  firstClassValue : Prop
  firstClassEstablished : firstClassValue

structure NativePOOExtension where
  usesCanonicalGerbilPoo : Prop
  canonicalLibraryEstablished : usesCanonicalGerbilPoo
  createsAlternativePooLibrary : Prop
  noAlternativePooLibrary : ¬ createsAlternativePooLibrary

structure ThreeLayerExtensionSurface where
  userLayerBounded : Prop
  packageAuthorLayerFirstClass : Prop
  nativeLayerGerbilPoo : Prop
  layersEstablished :
    userLayerBounded ∧
      packageAuthorLayerFirstClass ∧
      nativeLayerGerbilPoo

theorem flatUseCompositionIsAdmitted :
    AdmitsPublicCompositionSyntax .flatUseComposition := by
  simp [AdmitsPublicCompositionSyntax]

theorem nestedUseCompositionIsRejected :
    ¬ AdmitsPublicCompositionSyntax .nestedUseComposition := by
  simp [AdmitsPublicCompositionSyntax]

theorem clauseDslIsRejected :
    ¬ AdmitsPublicCompositionSyntax .clauseDsl := by
  simp [AdmitsPublicCompositionSyntax]

end PooFlowCoreProof.ProfileComposition.Composition
