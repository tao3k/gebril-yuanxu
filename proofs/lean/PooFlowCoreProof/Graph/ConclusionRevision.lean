-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Proof.Invalidation

import PooFlowCoreProof.Modules.Funflow.CausalCut

namespace PooFlowCoreProof.Graph.ConclusionRevision

open PooFlowCoreProof.Modules.Funflow.CausalCut

inductive ConclusionStateKind where
  | historical
  | active
  | superseded
  | retracted
  deriving DecidableEq, Repr

def IsActiveConclusion : ConclusionStateKind → Prop
  | .active => True
  | .historical => False
  | .superseded => False
  | .retracted => False

open LeanPoo.Proof

/-- A conclusion owns an actual dependent proof object. Its causal-cut identity
is the value at the declared cut key, not an unrelated provenance label. -/
structure CertifiedConclusion (Key : Type) (Value : Key → Type) (cutKey : Key) where
  identity : Nat
  policyRevision : Nat
  evidence : ProofObject Key Value
  cutIdentity : Value cutKey
  cutAligned : evidence.state cutKey = cutIdentity
  certified : Certificate evidence

/-- Both old and new immutable conclusions are retained. A semantic revision
requires discharge of the library-selected pending obligations at the new state. -/
def reviseConclusion [DecidableEq Key] {Value : Key → Type} {cutKey : Key}
    (before : CertifiedConclusion Key Value cutKey) (nextIdentity nextPolicy : Nat)
    (patch : Patch Key Value)
    (discharge : ∀ obligation, obligation ∈ pending before.evidence patch →
      obligation.holds (append before.evidence patch).state) :
    CertifiedConclusion Key Value cutKey × CertifiedConclusion Key Value cutKey :=
  (before, {
    identity := nextIdentity
    policyRevision := nextPolicy
    evidence := append before.evidence patch
    cutIdentity := (append before.evidence patch).state cutKey
    cutAligned := rfl
    certified := closePending before.evidence patch before.certified discharge })

theorem revisionRetainsHistoricalEvidence [DecidableEq Key]
    {Value : Key → Type} {cutKey : Key}
    (before : CertifiedConclusion Key Value cutKey) (identity policy : Nat)
    (patch : Patch Key Value) (discharge) :
    (reviseConclusion before identity policy patch discharge).1.evidence = before.evidence := rfl

structure LateEventCutRevision
    (EventIdentity CutIdentity RevisionIdentity : Type) where
  previousCut : ImmutableCausalCut EventIdentity CutIdentity
  revisedCut : ImmutableCausalCut EventIdentity CutIdentity
  cutIdentityChanged :
    revisedCut.cutIdentity ≠ previousCut.cutIdentity
  revisionIdentity : RevisionIdentity

structure RetractionReceipt
    (ConclusionIdentity CutIdentity ReasonIdentity ReceiptIdentity : Type) where
  conclusionIdentity : ConclusionIdentity
  revisedCutIdentity : CutIdentity
  reasonIdentity : ReasonIdentity
  receiptIdentity : ReceiptIdentity
  marksConclusionInactive : Prop
  inactiveEstablished : marksConclusionInactive
  deletesHistoricalEvidence : Prop
  preservesHistoricalEvidence : ¬ deletesHistoricalEvidence

structure ActiveConclusionSelection
    (ConclusionIdentity SelectionIdentity : Type) where
  candidates : List ConclusionIdentity
  activeConclusion : ConclusionIdentity
  activeIsCandidate : activeConclusion ∈ candidates
  selectionIdentity : SelectionIdentity
  isEligible : ConclusionIdentity → Prop
  activeEligible : isEligible activeConclusion
  uniqueActive :
    ∀ candidate ∈ candidates,
      isEligible candidate →
        candidate = activeConclusion

structure EffectCompensationProposal
    (EffectReceiptIdentity CompensationIntentIdentity : Type) where
  originalEffectReceiptIdentity : EffectReceiptIdentity
  compensationIntentIdentity : CompensationIntentIdentity
  carriesActionAuthority : Prop
  noActionAuthority : ¬ carriesActionAuthority

structure HistoricalCutReplay
    (CutIdentity ConclusionIdentity : Type) where
  cutIdentity : CutIdentity
  originalConclusion : ConclusionIdentity
  replayConclusion : ConclusionIdentity
  replayStable : replayConclusion = originalConclusion

theorem historicalConclusionIsNotActive :
    ¬ IsActiveConclusion .historical := by
  simp [IsActiveConclusion]

theorem supersededConclusionIsNotActive :
    ¬ IsActiveConclusion .superseded := by
  simp [IsActiveConclusion]

theorem retractedConclusionIsNotActive :
    ¬ IsActiveConclusion .retracted := by
  simp [IsActiveConclusion]

theorem selectedConclusionIsActive :
    IsActiveConclusion .active := by
  simp [IsActiveConclusion]

end PooFlowCoreProof.Graph.ConclusionRevision
