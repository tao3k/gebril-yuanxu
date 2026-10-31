-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SourceWindows
import LeanPoo.Functional.DeclarativeMetadata

/-! Ownership-scoped analysis routing is implemented by `object-types/contracts.ss` and
`admission/source.ss`. Its one-shot edge is modeled below, separately from the
finite port/contribution batching reference. An analysis mode is never a source
certificate. Native callbacks and complete interception remain explicit bounds.
The selected publication supplies requirements BEFORE prototype slot overriding. -/
namespace YuanxuProof.Admission.RootChild
namespace Routing
open LeanPoo.Functional

/-- These coordinates project native reference equality, not content equality. -/
structure Request where
  contract : Nat
  candidate : Nat
  context : Nat
  deriving Repr, DecidableEq

structure Edge where
  request : Request
  child : Bool
  deriving Repr, DecidableEq

inductive Mode where
  | independent | root | child
  deriving Repr, DecidableEq

def edgeMatches : Option Edge → Request → Bool
  | none, _ => false
  | some edge, request => edge.request == request

/-- The parameter is cleared BEFORE classification and replaceable callbacks,
even on a mismatched request. Only an owned responsibility edge can set it again. -/
def enter : Factory (Option Edge × Request) (fun _ => Mode × Option Edge) :=
  Factory.choose (fun input => edgeMatches input.1 input.2)
    (fun input => (if input.1.any Edge.child then .child else .root, none))
    (fun _ => (.independent, none))

def consume (pending : Option Edge) (request : Request) : Mode × Option Edge :=
  enter (pending, request)

def responsibilityEdge (mode : Mode) (request : Request) : Option Edge :=
  match mode with
  | .independent => none
  | .root | .child => some ⟨request, true⟩

theorem consumed_before_callbacks (pending : Option Edge) (request : Request) :
    (consume pending request).2 = none := by
  simp only [consume, enter, Factory.choose]
  split <;> rfl

theorem callback_reentry_is_independent (pending : Option Edge)
    (request callback : Request) :
    consume (consume pending request).2 callback = (.independent, none) := by
  rw [consumed_before_callbacks]
  rfl

theorem mismatched_request_is_independent (edge : Edge) (request : Request)
    (changed : edge.request ≠ request) :
    consume (some edge) request = (.independent, none) := by
  simp [consume, enter, Factory.choose, edgeMatches, changed]

theorem mismatched_request_cannot_delegate (edge : Edge) (request child : Request)
    (changed : edge.request ≠ request) :
    responsibilityEdge (consume (some edge) request).1 child = none := by
  rw [mismatched_request_is_independent edge request changed]
  rfl

theorem owned_responsibility_uses_child_analysis (root child : Request) :
    consume (responsibilityEdge (consume (some ⟨root, false⟩) root).1 child) child =
      (.child, none) := by
  simp [consume, enter, Factory.choose, edgeMatches, responsibilityEdge]

#guard consume (some ⟨⟨1, 2, 3⟩, false⟩) ⟨1, 2, 3⟩ == (.root, none)
#guard consume (some ⟨⟨1, 2, 3⟩, true⟩) ⟨1, 9, 3⟩ == (.independent, none)
#guard consume (some ⟨⟨1, 2, 3⟩, true⟩) ⟨1, 2, 9⟩ == (.independent, none)
end Routing

def quintSourceDigest : String :=
  "sha256:932b83c78816ec85fb6049ac7dda441b88fa95a07d9ab5215bbb032ac36511a2"

open LeanPoo.Proof
open SourceWindows

structure Config where
  receiver : Nat
  revision : Nat
  databasePort : Nat
  clientPort : Nat
  deriving DecidableEq, Repr

structure Contribution where
  origin : String
  port : Nat
  sources : List (String × String)
  deriving DecidableEq, Repr

def domain (config : Config) (parts : List Contribution) : Bool :=
  (1 ≤ config.databasePort && config.databasePort ≤ 65535) &&
  (config.clientPort == config.databasePort) &&
  parts.all (fun part => part.port == config.databasePort)

structure Analysis where
  candidate : Config
  contributions : List Contribution
  deriving DecidableEq, Repr

/-- Shape/child obligations are represented by the executable domain predicate.
Real arbitrary obligations still run; this projection does not memoize callbacks. -/
def analyze (config : Config) (parts : List Contribution) : Option Analysis :=
  if domain config parts then some ⟨config, parts⟩ else none

def inputs (parts : List Contribution) : List (String × String) :=
  parts.flatMap Contribution.sources

/-- `parts` is the authoritative publication collection. Exact list comparison
rejects missing/replaced origins, not merely an equal number of contributions.
`finalWorld` is acquired AFTER all callbacks, with an empty byte cache. -/
def rootCheck (config : Config) (parts : List Contribution)
    (evidence : Analysis) (finalWorld : World) : Bool :=
  (evidence.candidate == config) && (evidence.contributions == parts) &&
  domain config parts && (check (inputs parts) finalWorld empty).accepted

theorem root_sources (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World)
    (valid : rootCheck config parts evidence world = true) :
    Certificate (Source.sourceObject (inputs parts) world) := by
  apply (fresh_certificate _ _).mp
  simpa [rootCheck] using (Bool.and_eq_true_iff.mp valid).2

theorem child_sources (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World)
    (valid : rootCheck config parts evidence world = true)
    (child : Contribution) (member : child ∈ parts) :
    Certificate (Source.sourceObject child.sources world) := by
  have all := (fresh_exact _ _).mp ((Bool.and_eq_true_iff.mp valid).2)
  apply (Source.checkSources_certifies _ _).mp
  simp only [Source.checkSources, List.all_eq_true, beq_iff_eq]
  intro input found
  exact all input (List.mem_flatMap.mpr ⟨child, member, found⟩)

theorem requirements_retained (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World)
    (valid : rootCheck config parts evidence world = true) :
    ∀ part ∈ parts, part.port = config.databasePort := by
  have h : domain config parts = true := (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp valid).1).2
  simpa [domain, List.all_eq_true] using (Bool.and_eq_true_iff.mp h).2

theorem conflicting_ports_rejected (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World) (left right : Contribution)
    (l : left ∈ parts) (r : right ∈ parts) (different : left.port ≠ right.port) :
    rootCheck config parts evidence world ≠ true := by
  intro accepted
  have both := requirements_retained _ _ _ _ accepted
  exact different ((both left l).trans (both right r).symm)

theorem candidate_bound (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World)
    (valid : rootCheck config parts evidence world = true) : evidence.candidate = config := by
  simpa only [rootCheck, Bool.and_eq_true, beq_iff_eq] using
    (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp valid).1).1).1

theorem cached_parent_rejected (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World) (different : evidence.candidate ≠ config) :
    rootCheck config parts evidence world ≠ true := by
  intro accepted
  exact different (candidate_bound _ _ _ _ accepted)

theorem coverage_bound (config : Config) (parts : List Contribution)
    (evidence : Analysis) (world : World)
    (valid : rootCheck config parts evidence world = true) : evidence.contributions = parts := by
  exact beq_iff_eq.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp valid).1).1).2

theorem post_effect_change_rejected (config : Config) (parts : List Contribution)
    (evidence : Analysis) (after : World) (input : String × String)
    (member : input ∈ inputs parts) (changed : after input.1 ≠ some input.2) :
    rootCheck config parts evidence after ≠ true := by
  intro accepted
  exact Source.changedSourceCannotBeCertified _ _ input member changed
    (root_sources _ _ _ _ accepted)

/-- Compare the two schedules IN ONE stable world. This is not permission to
reuse bytes across effects, nor a proof that the runtime observation set is complete. -/
theorem batching_equivalent (parts : List Contribution) (world : World) :
    (check (inputs parts) world empty).accepted = true ↔
    ∀ part ∈ parts, (check part.sources world empty).accepted = true := by
  simp only [fresh_exact, inputs, List.mem_flatMap]
  constructor
  · intro all part member input found
    exact all input ⟨part, member, found⟩
  · intro all input found
    rcases found with ⟨part, member, inPart⟩
    exact all part member input inPart

/-- Deduplicate I/O, not obligations: both expected strings are still compared. -/
theorem shared_closure_one_read (path expectedLeft expectedRight : String) (world : World) :
    (check (inputs [⟨"postgresql", 5433, [(path, expectedLeft)]⟩,
                    ⟨"gitea", 5433, [(path, expectedRight)]⟩]) world empty).reads = 1 := by
  exact two_requirements_one_read world path expectedLeft expectedRight

open LeanPoo.Functional.DeclarativeMetadata

structure ReturnView where
  analysis : Analysis
  world : World

/-- Root admission is a return-time meaning check, using LeanPoo's existing
metadata protocol. No public child result can bypass this meaning predicate. -/
def rootCall : Contract Unit (Config × List Contribution) ReturnView where
  input := ⟨"final candidate and selected contributions", fun _ => True, fun _ => inferInstance⟩
  output := ⟨"analytic child result", fun _ => True, fun _ => inferInstance⟩
  meaning := fun _ request result => rootCheck request.1 request.2 result.analysis result.world = true
  decide := fun _ _ _ => inferInstance
  rule := .atom ()

theorem returned_invocation_sources {State Error : Type}
    (request : Config × List Contribution)
    (execute : (Config × List Contribution) → Except Error (ReturnView × State))
    (invocation : Invocation rootCall execute request) :
    Certificate (Source.sourceObject (inputs request.2) invocation.result.world) :=
  root_sources _ _ _ _ invocation.logic

/-- Rejection preserves the previous published state, not external side effects.
The supplied return world must be a fresh observation, not an effectful callback
executed inside a byte-cache window. -/
theorem stale_return_keeps_previous {State Error : Type} (old tentative : State)
    (request : Config × List Contribution) (result : ReturnView)
    (execute : (Config × List Contribution) → Except Error (ReturnView × State))
    (called : execute request = .ok (result, tentative))
    (input : String × String) (member : input ∈ inputs request.2)
    (changed : result.world input.1 ≠ some input.2) :
    rootCall.publish old execute request = (.error .logic, old) := by
  have invalid := post_effect_change_rejected request.1 request.2 result.analysis result.world input member changed
  have refused := rootCall.invoke_logic execute request result tentative trivial called trivial invalid
  apply rootCall.publish_refuses old execute request .logic
  simp [Contract.wrap, refused, Except.map]

private def child : Config := ⟨1, 1, 5433, 5433⟩
private def parts : List Contribution :=
  [⟨"postgresql", 5433, [("/config.json", "original")]⟩,
   ⟨"gitea", 5433, [("/config.json", "original")]⟩]
private def proofData : Analysis := ⟨child, parts⟩
#guard (analyze child parts).isSome
-- Analysis may succeed in a stale world; it grants NO source-bound authority.
#guard !rootCheck child parts proofData (fun _ => some "changed")
#guard rootCheck child parts proofData (fun _ => some "original")
#guard !rootCheck child parts {proofData with contributions := parts.take 1} (fun _ => some "original")
#guard !rootCheck child parts {proofData with candidate := ⟨0, 0, 5432, 5432⟩} (fun _ => some "original")
#guard (analyze {child with clientPort := 5432} parts).isNone
#guard (analyze {child with databasePort := 65536} parts).isNone
end YuanxuProof.Admission.RootChild
