-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Proof.Invalidation

import YuanxuProof.Modules.Funflow.CausalCut

namespace YuanxuProof.Modules.Funflow.ConclusionRevision

open YuanxuProof.Modules.Funflow.CausalCut

open LeanPoo.Proof

/-- A conclusion owns an actual dependent proof object. Its causal-cut identity
is the value at the declared cut key, not an unrelated provenance label. -/
structure CertifiedConclusion (Key : Type) (Value : Key → Type) (cutKey policyKey : Key) where
  identity : Nat
  policyRevision : Value policyKey
  evidence : ProofObject Key Value
  cutIdentity : Value cutKey
  cutAligned : evidence.state cutKey = cutIdentity
  policyAligned : evidence.state policyKey = policyRevision
  certified : Certificate evidence

/-- Both old and new immutable conclusions are retained. A semantic revision
requires discharge of the library-selected pending obligations at the new state. -/
def reviseConclusion [DecidableEq Key] {Value : Key → Type} {cutKey policyKey : Key}
    (before : CertifiedConclusion Key Value cutKey policyKey) (nextIdentity : Nat)
    (patch : Patch Key Value)
    (discharge : ∀ obligation, obligation ∈ pending before.evidence patch →
      obligation.holds (append before.evidence patch).state) :
    CertifiedConclusion Key Value cutKey policyKey × CertifiedConclusion Key Value cutKey policyKey :=
  (before, {
    identity := nextIdentity
    policyRevision := (append before.evidence patch).state policyKey
    evidence := append before.evidence patch
    cutIdentity := (append before.evidence patch).state cutKey
    cutAligned := rfl
    policyAligned := rfl
    certified := closePending before.evidence patch before.certified discharge })

theorem revisionRetainsHistoricalEvidence [DecidableEq Key]
    {Value : Key → Type} {cutKey policyKey : Key}
    (before : CertifiedConclusion Key Value cutKey policyKey) (identity : Nat)
    (patch : Patch Key Value) (discharge) :
    (reviseConclusion before identity patch discharge).1.evidence = before.evidence := rfl


end YuanxuProof.Modules.Funflow.ConclusionRevision
