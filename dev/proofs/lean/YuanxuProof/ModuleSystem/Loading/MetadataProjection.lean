-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.ContractConsequence
import LeanPoo.Functional.ConstructionCache

/-! Closed declaration projection and exact-context delayed construction.
The syntax decoder is a separate Scheme correspondence obligation: these
constructors cannot stand for arbitrary Scheme or authenticate native reads. -/
namespace YuanxuProof.ModuleSystem.Loading.MetadataProjection
open LeanPoo.Functional LeanPoo.Functional.Requirements

def quintSourceDigest : String := "sha256:c3789e2d9898d533d2d85a47284baf0d6e806ff498fe5184a25373acb40eb6ef"
def declaredPooRevision : String := "247a7eb8a40dca0843956da2cf93eb5b36dbdd62"
def declaredLeanPooRevision : String := "5d4587a30e2333fc5f935dac6163aa56ff16a2dc"

structure Dependency where
  alias : String
  target : String
  deriving DecidableEq, Repr

structure Metadata where
  identity : String
  dependencies : List Dependency
  sources : List (String × String)
  deriving DecidableEq, Repr

/-- Parsed first-order syntax, not an author-supplied purity flag. Unsupported
forms fail projection; a production reader must use its original guarded path. -/
inductive Declaration (Body : Type) where
  | direct (metadata : Metadata) (body : Body)
  | calculatedDependency (body : Body)
  | inheritedMetadata (body : Body)
  | extraTopForm (body : Body)
  | duplicateField (body : Body)
  deriving Repr

def project : Declaration Body → Option Metadata
  | .direct metadata _ => some metadata
  | _ => none

/-- Projection ignores the actual body; there is no body evaluator argument. -/
theorem roleBodyIrrelevant (metadata : Metadata) (left right : Body) :
    project (.direct metadata left) = project (.direct metadata right) := rfl

theorem dependenciesUnchanged (metadata : Metadata) (body : Body) :
    (project (.direct metadata body)).map Metadata.dependencies = some metadata.dependencies := rfl

theorem sourcesUnchanged (metadata : Metadata) (body : Body) :
    (project (.direct metadata body)).map Metadata.sources = some metadata.sources := rfl

theorem unsupportedRefused (body : Body) :
    project (.calculatedDependency body) = none ∧
    project (.inheritedMetadata body) = none ∧
    project (.extraTopForm body) = none ∧ project (.duplicateField body) = none := by
  simp [project]

/-- LeanPoo owns reuse of a closed immutable declaration. This theorem does
not authorize caching source currentness or a domain admission verdict. -/
theorem immutableDeclarationShared {K : Type} {V : K → Type} [DecidableEq K]
    {spec : LeanPoo.Functional.GeneralizedGraph.Declaration K V}
    (cache : LeanPoo.Functional.ConstructionCache.Cache spec) (order : List K) :
    (cache.retain order).closed = cache.closed ∧
    (cache.retain order).evaluated = [] ∧ (cache.retain order).reused = order :=
  ⟨LeanPoo.Functional.ConstructionCache.Cache.retain_closed cache order,
   LeanPoo.Functional.ConstructionCache.Cache.retain_work cache order⟩

/-- Receiver identity and every semantic revision are cache keys, not labels.
This is an explicit correspondence requirement on native memo ownership. -/
structure Context where
  receiver : Nat
  sourceRevision : Nat
  objectRevision : Nat
  selectionRevision : Nat
  phase : Nat
  deriving DecidableEq, Repr

variable {Key : Type} {Value : Context → Key → Type} {keys : List Key}
variable {Claim : ∀ c, Results Value c keys → Prop}

/-- Successful preparation retains the original functions, not a built scope. -/
theorem delayedFactoriesRetained (provider : Provider Context Key Value)
    (factories : Factories Context Value keys)
    (prepared : prepare provider keys = .ok factories) :
    Selected provider keys factories := (prepare_ok_iff _ _ _).mp prepared

/-- A cached parent cannot count as a child hit, even with equal source data. -/
theorem parentCannotHitChild (ready : Certified keys Claim)
    (parent child : Context) (different : parent.receiver ≠ child.receiver)
    (data : Snapshot ready parent) :
    ((ContextSlot.mk (some ⟨parent, data⟩)).read child).2.2 = false := by
  simp only [ContextSlot.read]
  split
  · rename_i same
    exact False.elim (different (congrArg Context.receiver same))
  · rfl

/-- Source, phase, selection or object changes replace the context slot. -/
theorem changedContextMiss (ready : Certified keys Claim)
    (old now : Context) (changed : old ≠ now) (data : Snapshot ready old) :
    ((ContextSlot.mk (some ⟨old, data⟩)).read now).2.2 = false := by
  simp [ContextSlot.read, changed]

/-- The output consumer still runs on every call, including dependency hits.
A runtime .admit result is not the cached data or an erased analytic proof. -/
theorem constructAtFinalContext (ready : Certified keys Claim)
    (slot : ContextSlot ready) {Output : Context → Type}
    (construct : ∀ c data, Claim c data → Output c) (context : Context) :
    (slot.consume construct context).1 = ready.consume construct context :=
  ContextSlot.consume_value slot construct context

/-- Strengthening a consequence never changes retained dependency functions. -/
theorem consequenceRetainsFactories (ready : Certified keys Claim)
    (Next : ∀ c, Results Value c keys → Prop)
    (derive : ∀ c data, Claim c data → Next c data) :
    (ready.entails Next derive).factories = ready.factories := rfl

/-- Runtime obligations and currentness are independent conjuncts; no cached
analytic certificate can remove either contributor or return-time check. -/
def mayPublish (a b current : Bool) : Bool := a && b && current

theorem publishRequiresBothAndCurrent (a b current : Bool)
    (accepted : mayPublish a b current = true) :
    a = true ∧ b = true ∧ current = true := by
  simpa [mayPublish, Bool.and_eq_true, and_assoc] using accepted

/-- Publication preflight is a distinct demand: descriptor validation may load
Types, but grants neither a domain scope nor a domain admission certificate. -/
structure Preflight where
  descriptorValid : Bool
  typesDemanded : Bool
  scopeDemanded : Bool
  domainAdmitted : Bool
  deriving DecidableEq, Repr

def preflight (descriptorValid : Bool) : Preflight :=
  ⟨descriptorValid, true, false, false⟩

theorem preflightKeepsScopeCold (valid : Bool) :
    (preflight valid).typesDemanded = true ∧
    (preflight valid).scopeDemanded = false ∧
    (preflight valid).domainAdmitted = false := ⟨rfl, rfl, rfl⟩

def publishAfterPreflight (checked : Preflight) (a b current : Bool) : Bool :=
  checked.descriptorValid && mayPublish a b current

theorem publicationRetainsDescriptorAndObligations (valid a b current : Bool)
    (accepted : publishAfterPreflight (preflight valid) a b current = true) :
    valid = true ∧ a = true ∧ b = true ∧ current = true := by
  simpa [publishAfterPreflight, preflight, mayPublish, Bool.and_eq_true, and_assoc]
    using accepted

end YuanxuProof.ModuleSystem.Loading.MetadataProjection
