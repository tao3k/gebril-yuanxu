-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import YuanxuProof.ModuleSystem.Graph.Aggregation

namespace YuanxuProof.Contribution.Qualification

abbrev CapabilityConstraint (Action : Type) :=
  YuanxuProof.ModuleSystem.Graph.Aggregation.CapabilityConstraint Action

structure ContributorAsset
    (ContributorIdentity SemanticOwnerIdentity AssetIdentity
      RevisionIdentity FacetIdentity : Type) where
  contributorIdentity : ContributorIdentity
  semanticOwnerIdentity : SemanticOwnerIdentity
  assetIdentity : AssetIdentity
  revisionIdentity : RevisionIdentity
  facets : FacetIdentity → Prop

abbrev ContributorCatalog
    (contributorCount industryCount : Nat)
    (Asset : Type) :=
  Fin contributorCount → Fin industryCount → Asset → Prop

def CatalogIncludes
    {contributorCount industryCount : Nat}
    {Asset : Type}
    (catalog : ContributorCatalog contributorCount industryCount Asset)
    (asset : Asset) : Prop :=
  ∃ contributor industry, catalog contributor industry asset

structure QualificationEnvelope
    (Asset Action FacetIdentity CoreContractIdentity : Type) where
  declaredFacet : Asset → FacetIdentity → Prop
  qualifiedFacet : Asset → FacetIdentity → Prop
  facetEvidence : Asset → FacetIdentity → Prop
  qualifiedCapability : Asset → CapabilityConstraint Action
  coreContractIdentity : CoreContractIdentity

/-- Qualification is derived from every declared facet and its evidence, rather
than a separate flag whose coverage is supplied as a universal assumption. -/
def QualificationEnvelope.qualifies
    (qualification : QualificationEnvelope Asset Action FacetIdentity CoreContractIdentity)
    (asset : Asset) : Prop :=
  ∀ facet, qualification.declaredFacet asset facet →
    qualification.qualifiedFacet asset facet ∧ qualification.facetEvidence asset facet

structure GovernanceRelations
    (Principal Asset Action Responsibility Evidence : Type) where
  owns : Principal → Asset → Prop
  maintains : Principal → Asset → Prop
  reviews : Principal → Asset → Prop
  approves : Principal → Asset → Prop
  publishes : Principal → Asset → Prop
  authorityEvidence : Evidence → Principal → Asset → Action → Prop
  responsibilityDeclared : Asset → Responsibility → Prop
  actionResponsibility : Asset → Action → Responsibility → Prop
  accountable : Principal → Asset → Responsibility → Prop
  responsibilityEvidence :
    Evidence → Principal → Asset → Responsibility → Prop

/-- Authorization is the existence of matching authority evidence in the supplied
relation. The model does not authenticate evidence or infer authority from ownership. -/
def GovernanceRelations.authorized
    (governance : GovernanceRelations Principal Asset Action Responsibility Evidence)
    (principal : Principal) (asset : Asset) (action : Action) : Prop :=
  ∃ evidence, governance.authorityEvidence evidence principal asset action

def UseCompositionAdmission
    {Asset Action FacetIdentity CoreContractIdentity : Type}
    (qualification :
      QualificationEnvelope
        Asset Action FacetIdentity CoreContractIdentity)
    (userAuthority : CapabilityConstraint Action)
    (asset : Asset)
    (action : Action) : Prop :=
  qualification.qualifies asset ∧
    qualification.qualifiedCapability asset action ∧
    userAuthority action

def GovernedUseCompositionAdmission
    {Principal Asset Action Responsibility Evidence
      FacetIdentity CoreContractIdentity : Type}
    (qualification :
      QualificationEnvelope
        Asset Action FacetIdentity CoreContractIdentity)
    (governance :
      GovernanceRelations
        Principal Asset Action Responsibility Evidence)
    (userAuthority : CapabilityConstraint Action)
    (principal : Principal)
    (asset : Asset)
    (action : Action) : Prop :=
  UseCompositionAdmission qualification userAuthority asset action ∧
    governance.authorized principal asset action ∧
    ∃ responsibility accountablePrincipal evidence,
      governance.actionResponsibility asset action responsibility ∧
      governance.responsibilityDeclared asset responsibility ∧
      governance.accountable accountablePrincipal asset responsibility ∧
      governance.responsibilityEvidence evidence accountablePrincipal asset responsibility

theorem missingFacetEvidenceBlocksUse
    (qualification : QualificationEnvelope Asset Action FacetIdentity CoreContractIdentity)
    (userAuthority : CapabilityConstraint Action) (asset : Asset) (action : Action)
    (facet : FacetIdentity) (declared : qualification.declaredFacet asset facet)
    (missing : ¬ qualification.facetEvidence asset facet) :
    ¬ UseCompositionAdmission qualification userAuthority asset action := by
  intro admitted
  exact missing ((admitted.1 facet declared).2)

theorem emptyContributorCatalogIncludesNoAsset
    {industryCount : Nat}
    {Asset : Type}
    (catalog : ContributorCatalog 0 industryCount Asset)
    (asset : Asset) :
    ¬ CatalogIncludes catalog asset := by
  intro included
  obtain ⟨contributor, _, _⟩ := included
  exact Fin.elim0 contributor

theorem emptyIndustryCatalogIncludesNoAsset
    {contributorCount : Nat}
    {Asset : Type}
    (catalog : ContributorCatalog contributorCount 0 Asset)
    (asset : Asset) :
    ¬ CatalogIncludes catalog asset := by
  intro included
  obtain ⟨_, industry, _⟩ := included
  exact Fin.elim0 industry

theorem governedAdmissionHasExplicitAuthorization
    {Principal Asset Action Responsibility Evidence
      FacetIdentity CoreContractIdentity : Type}
    (qualification :
      QualificationEnvelope
        Asset Action FacetIdentity CoreContractIdentity)
    (governance :
      GovernanceRelations
        Principal Asset Action Responsibility Evidence)
    (userAuthority : CapabilityConstraint Action)
    (principal : Principal)
    (asset : Asset)
    (action : Action)
    (admitted :
      GovernedUseCompositionAdmission
        qualification governance userAuthority
        principal asset action) :
    governance.authorized principal asset action :=
  admitted.2.1

theorem governedAdmissionHasAuthorityEvidence
    {Principal Asset Action Responsibility Evidence
      FacetIdentity CoreContractIdentity : Type}
    (qualification :
      QualificationEnvelope
        Asset Action FacetIdentity CoreContractIdentity)
    (governance :
      GovernanceRelations
        Principal Asset Action Responsibility Evidence)
    (userAuthority : CapabilityConstraint Action)
    (principal : Principal)
    (asset : Asset)
    (action : Action)
    (admitted :
      GovernedUseCompositionAdmission
        qualification governance userAuthority
        principal asset action) :
    ∃ evidence,
      governance.authorityEvidence
        evidence principal asset action :=
  admitted.2.1

end YuanxuProof.Contribution.Qualification
