-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.CertifiedConsumer

namespace YuanxuProof.ModuleSystem.Schema.Resolution

universe u

inductive ResolutionPhase where
  | structuralProjection
  | semanticAdmission
  | priorityResolution
  | canonicalCombination
  | contractAssembly
  | semanticEvaluation
  | runtimeAuthorization
  | disclosure
deriving Repr, DecidableEq

inductive ResolutionFailure where
  | structuralProjection
  | semanticAdmission
  | priorityConflict
  | canonicalCombination
  | contractViolation
  | semanticConflict
  | semanticCycle
  | runtimeAuthorization
  | runtimeEffect
  | disclosurePolicy
deriving Repr, DecidableEq

inductive MissingValueReason where
  | noContribution
  | explicitlyFiltered
deriving Repr, DecidableEq

inductive ResolutionOutcome (Value : Type u) where
  | resolved (value : Value)
  | missing (reason : MissingValueReason)
  | failed (failure : ResolutionFailure)
deriving Repr, DecidableEq

open LeanPoo.Functional
open LeanPoo.Functional.Requirements

/-- Select all required producers and certify their joint contract before any
runtime authorization. The authorization result, rather than an assumed phase
wrapper, is the only input from which a disclosure can be produced. -/
def prepareDisclosure
    {Context Key : Type} {Value : Context → Key → Type}
    (provider : Provider Context Key Value) (keys : List Key)
    (Claim : ∀ c, Results Value c keys → Prop)
    (admit : ∀ factories, Selected provider keys factories →
      ∀ c, Claim c (build factories c))
    {Authorization : (c : Context) → Results Value c keys → Type}
    {Output : Context → Type}
    (authorize : ∀ c data, Claim c data → Except ResolutionFailure (Authorization c data))
    (disclose : ∀ c data, Authorization c data → Output c) :
    Except Key (Factory Context (fun c => Except ResolutionFailure (Output c))) :=
  (prepareCertified provider keys Claim admit).map fun ready =>
    ready.consume (fun c data valid => (authorize c data valid).map (disclose c data))

/-- A denied effect never calls the disclosure function. The missing capability
error belongs to the outer preparation; runtime denial belongs to the inner result. -/
theorem deniedAuthorizationCannotDisclose
    {Context Key : Type} {Value : Context → Key → Type} {keys : List Key}
    {Claim : ∀ c, Results Value c keys → Prop} (ready : Certified keys Claim)
    {Authorization : (c : Context) → Results Value c keys → Type}
    {Output : Context → Type}
    (authorize : ∀ c data, Claim c data → Except ResolutionFailure (Authorization c data))
    (disclose : ∀ c data, Authorization c data → Output c)
    (context : Context) (failure : ResolutionFailure)
    (denied : authorize context (build ready.factories context) (ready.valid context) = .error failure) :
    ready.consume (fun c data valid => (authorize c data valid).map (disclose c data)) context =
      .error failure := by
  rw [Certified.consume_apply, denied]
  rfl

theorem failureCannotBeMissing
    {Value : Type u}
    (failure : ResolutionFailure)
    (reason : MissingValueReason) :
    (ResolutionOutcome.failed failure : ResolutionOutcome Value) ≠
      ResolutionOutcome.missing reason := by
  intro equality
  cases equality

theorem structuralFailureIsNotSemanticConflict :
    ResolutionFailure.structuralProjection ≠
      ResolutionFailure.semanticConflict := by
  decide

theorem runtimeAuthorizationFailureIsNotSemanticConflict :
    ResolutionFailure.runtimeAuthorization ≠
      ResolutionFailure.semanticConflict := by
  decide

theorem runtimeEffectFailureIsNotMissing
    {Value : Type u}
    (reason : MissingValueReason) :
    (ResolutionOutcome.failed ResolutionFailure.runtimeEffect :
        ResolutionOutcome Value) ≠
      ResolutionOutcome.missing reason :=
  failureCannotBeMissing ResolutionFailure.runtimeEffect reason

end YuanxuProof.ModuleSystem.Schema.Resolution
