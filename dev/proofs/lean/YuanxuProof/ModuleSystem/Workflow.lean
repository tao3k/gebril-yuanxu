-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Object.Definition
import LeanPoo.Object.SpecificationComposition
import LeanPoo.Functional.ContextPullback
import LeanPoo.Functional.ContractConsequence
import LeanPoo.Functional.Codec
import YuanxuProof.ModuleSystem.Schema.Association.Projection
import YuanxuProof.ModuleSystem.Schema.Query
import LeanPoo.Proof.Invalidation

/-! One executable Core scenario using the dependency's public API. C4 validates
module inheritance; it is not a scheduler or an SCC solver for workflow loops.
The Receipt is projected input, not authenticated native evidence. -/
namespace YuanxuProof.ModuleSystem.Workflow
open LeanPoo Functional Requirements
open YuanxuProof.ModuleSystem.Schema.Association
open YuanxuProof.ModuleSystem.Schema.Query

structure Context where
  view : View
  space : ElementSpace
  query : Query
  receipt : Projection.Receipt
  deriving DecidableEq

/-- Labels are presentation, never part of the cached semantic context. -/
structure Request where
  context : Context
  label : String

def effectiveChecks (view : View) : CheckIDs :=
  [view.receiver, view.sourceRevision, view.policyRevision]

/-- The same contribution order through the public POO declaration API.
Each derived prototype refines the inherited value, rather than copying a model. -/
def checkObject (view : View) : Except String (Object.Memoized String (fun _ => CheckIDs)) := do
  let base ← (Object.define (Key := String) (Value := fun _ => CheckIDs) "Base" do
    Object.Declaration.Builder.value "checks" [view.receiver]).mapError (fun _ => "base")
  let profile ← (base.extendWith "Profile" do
    Object.Declaration.Builder.modifyInherited "checks"
      (Option.map (· ++ [view.sourceRevision]))).mapError (fun _ => "profile")
  let policy ← (profile.extendWith "Policy" do
    Object.Declaration.Builder.modifyInherited "checks"
      (Option.map (· ++ [view.policyRevision]))).mapError (fun _ => "policy")
  return policy

/-- The total public plan semantics is suitable for kernel reduction. The
memoized reader has a partial thunk implementation and is exercised separately. -/
def composedChecks (view : View) : Except String CheckIDs := do
  let policy ← checkObject view
  return (policy.plan.resolve "checks" (fun _ => none)).getD []

def ResultBound (context : Context) (result : QueryResult) : Prop :=
  result.queryIdentity = context.query.identity ∧
  result.sourceRevision = context.space.revision ∧
  result.selectedIdentities = context.query.selectedIdentities ∧
  result.carriesActionAuthority = false ∧
  context.query.Admitted context.space ∧
  Projection.receiptGate context.view.contractRevision context.view.receiver
    context.view.sourceRevision context.receipt = true ∧
  Projection.CoreRule context.receipt ∧
  context.space.revision = context.view.sourceRevision ∧
  (composedChecks context.view).toOption = some (effectiveChecks context.view)

abbrev Outcome (context : Context) := Except String {result : QueryResult // ResultBound context result}

def checkedQuery (context : Context) : Outcome context :=
  if composed : (composedChecks context.view).toOption = some (effectiveChecks context.view) then
    if valid : Projection.receiptGate context.view.contractRevision context.view.receiver
        context.view.sourceRevision context.receipt = true then
      if evidenceLaw : Projection.CoreRule context.receipt then
        if aligned : context.space.revision = context.view.sourceRevision then
          match admitQuery context.space context.query with
          | .error error => .error error
          | .ok admitted => .ok ⟨evaluateQuery context.space context.query (admitted.property.1 ▸ admitted.property.2),
              rfl, rfl, rfl, rfl, admitted.property.1 ▸ admitted.property.2,
              valid, evidenceLaw, aligned, composed⟩
        else .error "source cut mismatch"
      else .error "undischarged receipt"
    else .error "uncorrelated contract receipt"
  else .error "POO contribution mismatch"

inductive Capability where
  | checks | result | missing
  deriving DecidableEq, Repr

def Value (context : Context) : Capability → Type
  | .checks => {checks : CheckIDs // checks = effectiveChecks context.view}
  | .result => Outcome context
  | .missing => Unit

abbrev requested : List Capability := [.checks, .result]

def baseProvider : Provider Context Capability Value
  | .checks => some fun context => ⟨effectiveChecks context.view, rfl⟩
  | .result => some checkedQuery
  | .missing => none

def moduleGraph : C4.Graph := {nodes := [
  {name := "Module", parentOrders := [["Profile", "Backend"]]},
  {name := "Profile", parentOrders := [["Base"]]},
  {name := "Backend", parentOrders := [["Base"]]}, {name := "Base"}]}

def providers (name : String) : Provider Context Capability Value :=
  if name == "Base" then baseProvider else fun _ => none

def Claim (context : Context) (data : Results Value context requested) : Prop :=
  data.1.val = effectiveChecks context.view

def prepare (graph : C4.Graph := moduleGraph) : Except String (Certified requested Claim) := do
  let order ← (C4.linearizeVerified graph "Module").mapError (fun _ => "invalid inheritance")
  let provider := assemble order providers
  (prepareCertified provider requested Claim (fun factories _ context =>
    (build factories context).1.property)).mapError (fun _ => "missing capability")

/-- This is a domain wire layout, built with Codec.represent, not another Codec. -/
def resultCodec : Codec QueryResult (QueryResult × String) String :=
  (Codec.identity QueryResult String).represent (fun result => (result, "core.query.v1"))
    Prod.fst (fun _ => rfl)

structure Report where
  label : String
  checks : CheckIDs
  result : Except String (QueryResult × String)

def report (request : Request) (data : Results Value request.context requested)
    (_valid : Claim request.context data) : Report :=
  ⟨request.label, data.1.val, data.2.1.map (fun result => resultCodec.encode result.val)⟩

theorem cached_checks_remain_current (ready : Certified requested Claim)
    (slot : ContextSlot ready) (request : Request) :
    (slot.consumeAlong Request.context report request).1.checks =
      effectiveChecks request.context.view := by
  rw [ContextSlot.consumeAlong_value]
  exact ready.valid request.context

theorem cached_output_uses_current_label (ready : Certified requested Claim)
    (slot : ContextSlot ready) (request : Request) :
    (slot.consumeAlong Request.context report request).1.label = request.label := by
  rw [ContextSlot.consumeAlong_value]
  rfl

theorem result_wire_roundtrip (result : QueryResult) :
    resultCodec.decode (resultCodec.encode result) = .ok result :=
  resultCodec.decode_encode result

/-- Both success and failure are retained at this exact semantic context. -/
def run (requests : List Request) : Except String (List (String × CheckIDs × Option Nat × Bool)) := do
  let ready ← prepare
  let mut slot := ContextSlot.empty ready
  let mut outputs := []
  for request in requests do
    let (output, next, hit) := slot.consumeAlong Request.context report request
    slot := next
    outputs := outputs ++ [(output.label, output.checks,
      output.result.toOption.map (fun wire => wire.1.sourceRevision), hit)]
  return outputs

def context : Context :=
  { view := ⟨7, 1, 3, 9, 0⟩
    space := ⟨3, ["object"]⟩
    query := ⟨"query", ["object"], true, true⟩
    receipt := ⟨true, 9, 7, 3, 9, 7, 3, true, [], true⟩ }

#guard (composedChecks context.view).toOption == some (effectiveChecks context.view)
#guard ((checkObject context.view).toOption.bind (fun object => object.read "checks")) ==
  (composedChecks context.view).toOption

-- These controls exercise actual library selection, cache and codec functions.
#guard (run [⟨context, "first"⟩, ⟨context, "second"⟩]).toOption ==
  some [("first", [7,3,0], some 3, false), ("second", [7,3,0], some 3, true)]
#guard (run [⟨context, "before"⟩,
  ⟨{context with view := {context.view with policyRevision := 1}}, "revised"⟩]).toOption ==
  some [("before", [7,3,0], some 3, false), ("revised", [7,3,1], some 3, false)]
#guard (run [⟨{context with receipt := {context.receipt with candidate := 99}}, "stale"⟩]).toOption ==
  some [("stale", [7,3,0], none, false)]
#guard (run [⟨{context with query := {context.query with selectedIdentities := ["missing"]}}, "outside"⟩]).toOption ==
  some [("outside", [7,3,0], none, false)]
#guard (run [⟨context, "first"⟩,
  ⟨{context with space := ⟨4, ["object"]⟩}, "new-cut"⟩, ⟨context, "return"⟩]).toOption ==
  some [("first", [7,3,0], some 3, false), ("new-cut", [7,3,0], none, false),
        ("return", [7,3,0], some 3, false)]
#guard (prepare {nodes := [{name := "Module", parentOrders := [["Module"]]}]}).toOption.isNone
def missingCapability : Except String (Factories Context Value [.missing]) := do
  let order ← (C4.linearizeVerified moduleGraph "Module").mapError (fun _ => "graph")
  (Requirements.prepare (assemble order providers) [.missing]).mapError (fun _ => "missing")
#guard missingCapability.toOption.isNone
#guard (run [⟨{context with receipt := {context.receipt with classified := false}}, "forged"⟩]).toOption ==
  some [("forged", [7,3,0], none, false)]

/-! Proof revision uses the same checked semantic context as the cache above. -/
namespace Revision
open LeanPoo.Proof

inductive Key where
  | semantic | label
  deriving DecidableEq

def Field : Key → Type
  | .semantic => Context
  | .label => String

def sourceAligned : Obligation Key Field where
  dependencies := [.semantic]
  holds := fun state => (state .semantic).space.revision =
    (state .semantic).view.sourceRevision
  stable := by
    intro before after same valid
    rw [← same .semantic (by simp)]
    exact valid

def original : ProofObject Key Field where
  state := fun | .semantic => context | .label => "first"
  obligations := [sourceAligned]

theorem certified : Certificate original := by
  intro obligation member
  have equal : obligation = sourceAligned := by simpa [original] using member
  subst obligation
  rfl

def relabel : Patch Key Field := Patch.set .label "second"

theorem label_retains_evidence :
    sourceAligned.holds (append original relabel).state := by
  apply reuse original relabel certified sourceAligned (by simp [original])
  intro key dependency touched
  have equal : key = .semantic := by simpa [sourceAligned] using dependency
  subst key
  simp [relabel, Patch.set] at touched

def revise : Patch Key Field := Patch.set .semantic
  {context with view := {context.view with policyRevision := 1}}

theorem revision_requires_discharge : sourceAligned ∈ pending original revise := by
  apply (mem_pending_iff original revise sourceAligned).mpr
  apply Or.inl
  refine ⟨by simp [original], ?_⟩
  intro unaffected
  exact unaffected .semantic (by simp [sourceAligned]) (by simp [revise, Patch.set])

theorem revision_certified : Certificate (append original revise) := by
  apply closePending original revise certified
  intro obligation member
  have equal : obligation = sourceAligned := by
    have owned := (mem_pending_iff original revise obligation).mp member
    rcases owned with old | added
    · simpa [original] using old.1
    · simp [revise, Patch.set] at added
  subst obligation
  rfl

def stale : Patch Key Field := Patch.set .semantic
  {context with space := ⟨4, ["object"]⟩}

theorem stale_cannot_be_certified : ¬ Certificate (append original stale) := by
  intro certificate
  have invalid := certificate sourceAligned (by simp [append, original])
  change 4 = 3 at invalid
  cases invalid

end Revision

end YuanxuProof.ModuleSystem.Workflow
