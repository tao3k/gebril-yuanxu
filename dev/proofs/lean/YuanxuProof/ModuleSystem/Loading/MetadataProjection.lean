-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.ContractConsequence
import LeanPoo.Functional.ConstructionCache
import Std.Data.HashSet.Lemmas

/-! Closed declaration projection and exact-context delayed construction.
The syntax decoder is a separate Scheme correspondence obligation: these
constructors cannot stand for arbitrary Scheme or authenticate runtime reads. -/
namespace YuanxuProof.ModuleSystem.Loading.MetadataProjection
open LeanPoo.Functional LeanPoo.Functional.Requirements

/-! Context admission currently repeats a namespace list search for every
selected identity. The index is per validation, not a cached acceptance. This
law is only about already obtained immutable-in-the-window symbol values;
actual warm receiver/observer routing is a separate Scheme correspondence. -/
namespace SelectionIndex
def build : List String → Std.HashSet String
  | [] => {}
  | name :: rest => (build rest).insert name

theorem lookup_exact (names : List String) (name : String) :
    (build names).contains name = names.contains name := by
  induction names with
  | nil => simp [build]
  | cons first rest ih =>
    by_cases same : first = name
    · subst first
      simp [build, Std.HashSet.contains_insert, List.contains_cons]
    · simp [build, Std.HashSet.contains_insert, ih, List.contains_cons,
        same, Ne.symm same]

theorem selected_membership_exact (names selected : List String) :
    selected.all (fun name => (build names).contains name) =
      selected.all (fun name => names.contains name) := by
  simp only [lookup_exact]

theorem first_missing_unchanged (names selected : List String) :
    selected.find? (fun name => !(build names).contains name) =
      selected.find? (fun name => !names.contains name) := by
  simp only [lookup_exact]

inductive Eligibility where
  | denied | selected | consultPolicy
  deriving DecidableEq

def eligibility (denied selected : Bool) : Eligibility :=
  if denied then .denied else if selected then .selected else .consultPolicy

theorem indexed_eligibility_preserves_precedence (denied selected : List String)
    (name : String) :
    eligibility ((build denied).contains name) ((build selected).contains name) =
    eligibility (denied.contains name) (selected.contains name) := by
  simp only [lookup_exact]

def indexedEligibility (captured live : List String × List String)
    (sameWindow : Bool) (name : String) : Eligibility :=
  if sameWindow then
    eligibility ((build captured.1).contains name) ((build captured.2).contains name)
  else
    eligibility (live.1.contains name) (live.2.contains name)

theorem indexed_eligibility_requires_live_payload
    (captured live : List String × List String) (sameWindow : Bool)
    (stable : sameWindow = true → captured = live) (name : String) :
    indexedEligibility captured live sameWindow name =
      eligibility (live.1.contains name) (live.2.contains name) := by
  cases sameWindow with
  | false => rfl
  | true =>
    rw [stable rfl]
    exact indexed_eligibility_preserves_precedence _ _ _

example : indexedEligibility ([], ["owner"]) (["owner"], ["owner"]) true "owner" ≠
    indexedEligibility ([], ["owner"]) (["owner"], ["owner"]) false "owner" := by
  simp [indexedEligibility, lookup_exact, eligibility]
end SelectionIndex

namespace SourceReadWindow

def observe (retained : Option String) (read : Unit → String) : String :=
  retained.getD (read ())

theorem shared_physical_text_preserves_each_comparison
    (read : Unit → String) (first second : String) :
    (first == observe none read, second == observe (some (read ())) read) =
      (first == read (), second == read ()) := rfl

theorem fresh_window_reads_post_effect_text (before after expected : String)
    (accepted : before = expected) (changed : after ≠ before) :
    (expected == observe none (fun _ => after)) = false := by
  subst expected
  simp [observe, Ne.symm changed]

end SourceReadWindow

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
  | privateSourceImports (body : Body)
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
    project (.extraTopForm body) = none ∧ project (.duplicateField body) = none ∧
    project (.privateSourceImports body) = none := by
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
This is an explicit correspondence requirement on runtime memo ownership. -/
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
