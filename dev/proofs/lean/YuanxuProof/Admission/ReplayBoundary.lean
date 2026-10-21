-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReturnWindows

/-! A closed structural replay projection, not a purity tag for arbitrary MOP
callbacks. Preserve ordered diagnostics as well as source acceptance. Native
producer/metadata/observer closure is a correspondence obligation, not an axiom. -/
namespace YuanxuProof.Admission.ReplayBoundary
open SourceWindows

def quintSourceDigest : String :=
  "sha256:89be4e16c24f5f34819f94700e09d88cbd8fe6ee1ee700ceb8d9ff4d0060547e"

structure Request where
  path : String
  expected : String
  message : String
  location : String
  deriving DecidableEq, Repr

-- Coordinates stand for native reference/revision equality, not content equality.
structure Binding where
  receiver : Nat
  revision : Nat
  instanceId : Nat
  record : Nat
  value : Nat
  deriving DecidableEq, Repr

inductive Op where
  | source (request : Request)
  | token (key : String) (recorded current : Binding)
  deriving DecidableEq, Repr

inductive Issue where
  | source (request : Request)
  | staleToken (key : String)
  deriving DecidableEq, Repr

structure Result where
  issue : Option Issue
  cache : Bytes
  reads : Nat
  observed : List Request

/-- Ordinary source checks and structural token comparisons; no function-valued
callback, getter, hook or observer occurs in this operation algebra. -/
def run : List Op → World → Bytes → Result
  | [], _, cache => ⟨none, cache, 0, []⟩
  | .source request :: rest, world, cache =>
    let loaded := fetch cache world request.path
    let cost := if (cache request.path).isSome then 0 else 1
    if loaded.1 == some request.expected then
      let tail := run rest world loaded.2
      ⟨tail.issue, tail.cache, cost + tail.reads, request :: tail.observed⟩
    else ⟨some (.source request), loaded.2, cost, []⟩
  | .token key recorded current :: rest, world, cache =>
    if recorded == current then run rest world cache
    else ⟨some (.staleToken key), cache, 0, []⟩

def firstIssue : List Op → World → Option Issue
  | [], _ => none
  | .source request :: rest, world =>
    if world request.path == some request.expected then firstIssue rest world
    else some (.source request)
  | .token key recorded current :: rest, world =>
    if recorded == current then firstIssue rest world else some (.staleToken key)

/-- Sound byte reuse IN THE SAME ORDER preserves the exact first source request
(message and location included), or the exact stale-token failure. -/
theorem ordered_diagnostic_exact (ops : List Op) (world : World) (cache : Bytes)
    (sound : Sound cache world) :
    (run ops world cache).issue = firstIssue ops world := by
  induction ops generalizing cache with
  | nil => rfl
  | cons op rest ih =>
    cases op with
    | source request =>
      simp only [run, firstIssue, fetch_value cache world request.path sound]
      split
      · exact ih _ (fetch_sound cache world request.path sound)
      · rfl
    | token key recorded current =>
      simp only [run, firstIssue]
      split
      · exact ih _ sound
      · rfl

def sources : List Op → List Request
  | [] => []
  | .source request :: rest => request :: sources rest
  | .token _ _ _ :: rest => sources rest

/-- Successful replay enrolls every source operation, in order, without a
field list or traversing an unselected branch. Duplicates are NOT overriding. -/
theorem successful_coverage (ops : List Op) (world : World) (cache : Bytes)
    (accepted : (run ops world cache).issue = none) :
    (run ops world cache).observed = sources ops := by
  induction ops generalizing cache with
  | nil => rfl
  | cons op rest ih =>
    cases op with
    | source request =>
      simp only [run] at accepted ⊢
      split at accepted <;> simp_all [sources]
    | token key recorded current =>
      simp only [run] at accepted ⊢
      split at accepted <;> simp_all [sources]

theorem sources_append (left right : List Op) :
    sources (left ++ right) = sources left ++ sources right := by
  induction left with
  | nil => rfl
  | cons op rest ih => cases op <;> simp [sources, ih]

/-- Each dependency tree lowers structurally. This does not certify a raw
make-slot-read whose current? slot contains an arbitrary procedure. -/
inductive Replay where
  | leaf (ops : List Op)
  | branch (left right : Replay)

def lower : Replay → List Op
  | .leaf ops => ops
  | .branch left right => lower left ++ lower right

theorem both_branches_retained (left right : Replay) :
    sources (lower (.branch left right)) =
      sources (lower left) ++ sources (lower right) := sources_append _ _

def input (request : Request) : String × String := (request.path, request.expected)

/-- Projection of the existing collector's first-observed (path,text) policy.
The first message/location stays attached; a different expectation is retained. -/
def enroll (seen : List Request) (request : Request) : List Request :=
  if input request ∈ seen.map input then seen else seen ++ [request]

theorem enroll_complete (seen : List Request) (request : Request) (key : String × String) :
    key ∈ (enroll seen request).map input ↔
      key ∈ seen.map input ∨ key = input request := by
  unfold enroll
  split <;> simp_all

theorem enroll_retains_earlier (seen : List Request) (request earlier : Request)
    (member : earlier ∈ seen) : earlier ∈ enroll seen request := by
  unfold enroll
  split <;> simp_all

/-- Appending a final collector does not change an earlier ordered failure. -/
theorem failing_prefix_preserved (early suffix : List Op) (world : World)
    (issue : Issue) (failed : firstIssue early world = some issue) :
    firstIssue (early ++ suffix) world = some issue := by
  induction early with
  | nil => simp [firstIssue] at failed
  | cons op rest ih =>
    cases op with
    | source request =>
      simp only [firstIssue] at failed ⊢
      split at failed <;> simp_all [firstIssue]
    | token key recorded current =>
      simp only [firstIssue] at failed ⊢
      split at failed <;> simp_all [firstIssue]

private def json : Request :=
  ⟨"postgresql.json", "original", "configuration source changed", "postgresql.json:1"⟩
private def old : Binding := ⟨1, 0, 1, 1, 5432⟩
private def child : Binding := ⟨2, 1, 2, 2, 5433⟩
private def changed : World := fun _ => some "changed"

-- Complete source coverage and structural replay STILL do not permit moving
-- a JSON failure after a stale-token failure.
theorem moving_check_changes_diagnostic :
    firstIssue [.source json, .token "pipeline" old child] changed =
      some (.source json) ∧
    firstIssue [.token "pipeline" old child, .source json] changed =
      some (.staleToken "pipeline") := by decide

theorem parent_token_rejected :
    (run [.token "pipeline" old child] changed empty).issue =
      some (.staleToken "pipeline") := by decide

private def other : Request := { json with expected := "other", location := "team.ss:7" }
theorem conflicting_source_requirement_retained :
    (run [.source json, .source other] (fun _ => some "original") empty).issue =
      some (.source other) := by decide

private def reworded : Request :=
  { json with message := "stale selected build input", location := "publication.ss:4" }

-- Acceptance-equivalent input pairs do not guarantee diagnostic equivalence.
theorem changing_first_origin_changes_diagnostic :
    firstIssue [.source json] changed ≠ firstIssue [.source reworded] changed := by decide

end YuanxuProof.Admission.ReplayBoundary
