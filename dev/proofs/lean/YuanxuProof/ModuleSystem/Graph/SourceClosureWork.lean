-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission

namespace YuanxuProof.ModuleSystem.Graph.SourceClosureWork
open TestAdmission

def quintSourceDigest : String :=
  "sha256:de5fa7f5654cfbe5fc237300efa58a702d93b7bc0ecf4b74b0de15d972b2576b"

def sourcePrefixQuintDigest : String :=
  "sha256:220ae116181f9cc532ae22e1a1c77bb3a3bc48d79d860be5af1994f8a3335299"

def dependencyContinuationQuintDigest : String :=
  "sha256:dccabe4676bfd5e03f67a72e741884f75c19082b2c7c5280d95fb77afa581dca"

def readerEffectSupportQuintDigest : String :=
  "sha256:1a0c47ec0768b6cd9a3951810270837a02f5d13ff2b2bde40d13a3df38c15146"

def candidatePublicationQuintDigest : String :=
  "sha256:f08dd0b128c545d405710bf8996e78208a216334246d2c9407d1b8ff1d7414c7"

def candidateLocationQuintDigest : String :=
  "sha256:5fff9eb236d3f1f61fd2213e7220e6111166f4fcdfc81ddd1551debfd6dd061b"

def compilerEnrollmentQuintDigest : String :=
  "sha256:8ed21526e5da02e6e8e65f516057eff095da7ac1ce438746f6589f88879a2d8f"

def authoringStageQuintDigest : String :=
  "sha256:17f703653d33e59f7271dbb5be310d4a5c97a57e914e1d5f444e72fd79af3699"

def carrierReturnQuintDigest : String :=
  "sha256:91c65da73c3eb50692ae522454be020a2f413d38cfdb09c4924df32eb5c0f737"

def carrierAdmissionQuintDigest : String :=
  "sha256:5880421305bd18369237ac7ab2fa71f745707d26f0e9bfa6b9a2dd5638eea4f0"

structure Work (Node : Type) where
  discovery : Discovery Node
  pops : Nat
  edges : Nat

def step [DecidableEq Node] (deps : Node → List Node) (s : Work Node) : Work Node :=
  match s.discovery.pending with
  | [] => s
  | node :: _ =>
    ⟨advance deps s.discovery, s.pops + 1,
      s.edges + (if node ∈ s.discovery.seen then 0 else (deps node).length)⟩

def run [DecidableEq Node] (deps : Node → List Node) : Nat → Work Node → Work Node
  | 0, s => s
  | fuel + 1, s => run deps fuel (step deps s)

-- Counts queue removals, including repeated edges, separately from expansions.
-- Hash lookup, source bytes, native macro expansion and GC are not unit-cost
-- consequences of this theorem.
def Accounting (roots : Nat) (s : Work Node) : Prop :=
  s.pops + s.discovery.pending.length = roots + s.edges

theorem step_accounting [DecidableEq Node] (deps : Node → List Node)
    (roots : Nat) (s : Work Node) (h : Accounting roots s) :
    Accounting roots (step deps s) := by
  rcases s with ⟨⟨seen, pending⟩, pops, edges⟩
  cases pending with
  | nil => exact h
  | cons node rest =>
    by_cases found : node ∈ seen
    · simpa [Accounting, step, advance, found, Nat.add_assoc, Nat.add_comm,
        Nat.add_left_comm] using h
    · simp only [Accounting, List.length_cons] at h
      simp [Accounting, step, advance, found, List.length_append]
      omega

theorem run_accounting [DecidableEq Node] (deps : Node → List Node)
    (roots : Nat) (fuel : Nat) (s : Work Node) (h : Accounting roots s) :
    Accounting roots (run deps fuel s) := by
  induction fuel generalizing s with
  | zero => exact h
  | succ fuel ih => exact ih _ (step_accounting deps roots s h)

theorem queue_work_bound [DecidableEq Node] (deps : Node → List Node)
    (roots : List Node) (fuel : Nat) :
    (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).pops ≤
      roots.length + (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).edges := by
  have h := run_accounting deps roots.length fuel ⟨⟨[], roots⟩, 0, 0⟩ (by simp [Accounting])
  unfold Accounting at h
  omega

def charged (deps : Node → List Node) (seen : List Node) : Nat :=
  (seen.map fun node => (deps node).length).sum

theorem step_edge_accounting [DecidableEq Node] (deps : Node → List Node)
    (s : Work Node) (h : s.edges = charged deps s.discovery.seen) :
    (step deps s).edges = charged deps (step deps s).discovery.seen := by
  rcases s with ⟨⟨seen, pending⟩, pops, edges⟩
  cases pending with
  | nil => exact h
  | cons node rest =>
    by_cases found : node ∈ seen <;>
      simp_all [step, advance, charged, Nat.add_comm]

theorem run_edge_accounting [DecidableEq Node] (deps : Node → List Node)
    (fuel : Nat) (s : Work Node) (h : s.edges = charged deps s.discovery.seen) :
    (run deps fuel s).edges = charged deps (run deps fuel s).discovery.seen := by
  induction fuel generalizing s with
  | zero => exact h
  | succ fuel ih => exact ih _ (step_edge_accounting deps s h)

theorem run_projects_discovery [DecidableEq Node] (deps : Node → List Node)
    (fuel : Nat) (s : Work Node) :
    (run deps fuel s).discovery = discover deps fuel s.discovery := by
  induction fuel generalizing s with
  | zero => rfl
  | succ fuel ih =>
    rw [run, ih]
    have projection : (step deps s).discovery = advance deps s.discovery := by
      cases h : s.discovery.pending <;> simp [step, h, advance]
    rw [projection]
    rfl

theorem expanded_identities_unique [DecidableEq Node] (deps : Node → List Node)
    (roots : List Node) (fuel : Nat) :
    (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).discovery.seen.Nodup := by
  rw [run_projects_discovery]
  exact discover_preserves_unique_reads deps fuel ⟨[], roots⟩ (by simp)

-- A narrower guard is sound only if the operation's ACTUAL support is covered.
-- Four role files, two preceding-prefix and two completed-prefix barriers per
-- publication. Tool/package checks and source preparation are excluded. This
-- is the audited reader/link call-chain cost, not DFS expansion work.
def prefixGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => prefixGuardReads n + 8 * (2 * n + 1)

theorem prefix_guard_reads_quadratic (n : Nat) :
    prefixGuardReads n = 8 * n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [prefixGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

-- The closed directory operation checks only its metadata support. The reader
-- still checks complete source support before any opaque declaration callback.
-- Expansion and Contract admission still have separate full tail checks.
def pairedGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => pairedGuardReads n + 12 * n + 8

theorem paired_guard_reads (n : Nat) :
    pairedGuardReads n = 6 * n * n + 2 * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [pairedGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

theorem paired_prefix_never_more_reads (n : Nat) :
    pairedGuardReads n ≤ prefixGuardReads n := by
  induction n with
  | zero => exact Nat.le_refl 0
  | succ n ih =>
    simp only [pairedGuardReads, prefixGuardReads, Nat.mul_add] at *
    omega

-- Native paired selection: complete entry and declaration-return checks for
-- each module, then ONE full closure check before Feature/decision execution.
-- The final Graph check is unchanged and excluded on both sides, as are
-- compiler-tool/package observations. Custom/open paths keep pairedGuardReads.
def declarationGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => declarationGuardReads n + 8 * n + 4

def dependencyGuardReads (n : Nat) : Nat := declarationGuardReads n + 4 * n

theorem declaration_guard_reads (n : Nat) :
    declarationGuardReads n = 4 * n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [declarationGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

theorem dependency_guard_reads (n : Nat) :
    dependencyGuardReads n = 4 * n * n + 4 * n := by
  simp [dependencyGuardReads, declaration_guard_reads]

theorem dependency_guard_savings (n : Nat) :
    pairedGuardReads (n + 1) = dependencyGuardReads (n + 1) + 2 * n * (n + 1) := by
  rw [paired_guard_reads, dependency_guard_reads]
  simp only [Nat.mul_add, Nat.add_mul, Nat.mul_assoc]
  omega

-- Reuse is not an authority token: the closed prefix must preserve EVERY
-- captured source, native metadata receiver and ancestor revision. The native
-- audit and negative tests establish this premise at the paired call site.
theorem closed_prefix_preserves_entry
    (support : List Node) (expected eligible entry : Node → Nat)
    (checked : ∀ node, node ∈ support → expected node = eligible node)
    (closed : ∀ node, node ∈ support → eligible node = entry node) :
    ∀ node, node ∈ support → expected node = entry node := by
  intro node demanded
  exact (checked node demanded).trans (closed node demanded)

theorem changed_prefix_cannot_reuse (support : List Node)
    (expected entry : Node → Nat) (node : Node)
    (covered : node ∈ support) (changed : expected node ≠ entry node) :
    ¬ (∀ node, node ∈ support → expected node = entry node) := by
  intro accepted
  exact changed (accepted node covered)

-- A narrower guard is sound only if the operation's ACTUAL support is covered.
-- The finite Quint effects explore changes; this theorem quantifies over any
-- identity type and revisions. It cannot certify an opaque Scheme callback's
-- support by inspecting its name or source path.
theorem covered_guard_preserves_currentness
    (required checked : List Node) (before now : Node → Nat)
    (coverage : ∀ node, node ∈ required → node ∈ checked)
    (current : ∀ node, node ∈ checked → before node = now node) :
    ∀ node, node ∈ required → before node = now node := by
  intro node demanded
  exact current node (coverage node demanded)

-- Subject is a reference-identity projection, NOT structural object equality.
-- The native producer may normalize raw input into another receiver. Transfer
-- support only to the exact admitted reference saved by the linker. This law
-- does not certify callbacks as pure or eliminate the return-time source guard.
theorem checked_subject_guard_covers {Subject : Type}
    (support : Subject → List Node) (checked stored : Subject)
    (observed : List Node) (before now : Node → Nat)
    (sameSubject : stored = checked)
    (coverage : ∀ node, node ∈ support checked → node ∈ observed)
    (current : ∀ node, node ∈ observed → before node = now node) :
    ∀ node, node ∈ support stored → before node = now node := by
  subst stored
  exact covered_guard_preserves_currentness (support checked) observed before now
    coverage current

-- The caller establishes location-demand ⊆ metadata support from the actual
-- native directory implementation; it must not substitute metadata support
-- for the subsequent reader's complete support. Apply the same projection
-- theorem at two DIFFERENT operation boundaries, with independently current
-- observations (not a cached global approval across callbacks).
theorem location_then_reader_current
    (location metadata readerSupport : List Node)
    (before located readerEntry : Node → Nat)
    (locationCovered : ∀ node, node ∈ location → node ∈ metadata)
    (metadataCurrent : ∀ node, node ∈ metadata → before node = located node)
    (fullEntry : ∀ node, node ∈ readerSupport → before node = readerEntry node) :
    (∀ node, node ∈ location → before node = located node) ∧
    (∀ node, node ∈ readerSupport → before node = readerEntry node) := by
  exact ⟨covered_guard_preserves_currentness location metadata before located
           locationCovered metadataCurrent, fullEntry⟩

theorem omitted_support_can_escape [DecidableEq Node]
    (checked : List Node) (missing : Node) (absent : missing ∉ checked) :
    ∃ before now : Node → Nat,
      (∀ node, node ∈ checked → before node = now node) ∧
      before missing ≠ now missing := by
  refine ⟨fun _ => 0, fun node => if node = missing then 1 else 0, ?_, ?_⟩
  · intro node member
    have different : node ≠ missing := by
      intro same
      exact absent (same ▸ member)
    simp [different]
  · simp

-- Coverage is necessary, not merely sufficient, when a guard promises
-- currentness for EVERY possible source revision. Native import discovery
-- alone does not establish coverage of an initializer's ambient effects.
theorem universally_sound_guard_iff_coverage [DecidableEq Node]
    (required checked : List Node) :
    (∀ before now : Node → Nat,
      (∀ node, node ∈ checked → before node = now node) →
      ∀ node, node ∈ required → before node = now node) ↔
    (∀ node, node ∈ required → node ∈ checked) := by
  constructor
  · intro sound node demanded
    by_cases member : node ∈ checked
    · exact member
    · obtain ⟨before, now, current, changed⟩ := omitted_support_can_escape checked node member
      exact False.elim (changed (sound before now current node demanded))
  · intro coverage before now current
    exact covered_guard_preserves_currentness required checked before now coverage current

-- A certified operation's cost is its real support width. The theorem does
-- not manufacture the certification from native import edges or object names.
def operationReads (widths : List Nat) : Nat := widths.sum

theorem bounded_operation_support (widths : List Nat) (bound : Nat)
    (bounded : ∀ width ∈ widths, width ≤ bound) :
    operationReads widths ≤ bound * widths.length := by
  induction widths with
  | nil => simp [operationReads]
  | cons width rest ih =>
    have head := bounded width (by simp)
    have tail := ih (fun value member => bounded value (by simp [member]))
    simp only [operationReads, List.sum_cons, List.length_cons, Nat.mul_succ] at *
    omega

-- Local admission is not Graph visibility. Commit checks ALL selected support
-- independently of the earlier candidate revision, including a source which
-- changed only after local admission. No confinement of arbitrary IO is assumed.
theorem candidate_commit_current
    (selected finalChecked : List Node) (before commit : Node → Nat)
    (complete : ∀ node, node ∈ selected → node ∈ finalChecked)
    (freshCommit : ∀ node, node ∈ finalChecked → before node = commit node) :
    ∀ node, node ∈ selected → before node = commit node :=
  covered_guard_preserves_currentness selected finalChecked before commit complete freshCommit

-- Projection must preserve every actual requirement. Once that correspondence
-- is established, changes outside semantic support cannot make its guard fail.
-- This does not infer non-escape or purity for arbitrary initializer objects.
theorem scratch_outside_support_preserves_guard
    (support : List Node) (before initialized now : Node → Nat)
    (checked : ∀ node, node ∈ support → before node = initialized node)
    (stable : ∀ node, node ∈ support → initialized node = now node) :
    ∀ node, node ∈ support → before node = now node := by
  intro node required
  exact (checked node required).trans (stable node required)

theorem failed_candidate_keeps_previous {Value : Type} (previous candidate : Value) :
    (if false then candidate else previous) = previous := rfl

-- Count real support widths, not the accumulated publication prefix. Open
-- callbacks retain their independently charged full work; no linear bound is
-- claimed for N open callbacks each of which depends on the complete Graph.
def stagedGuardReads (widths : List Nat) (fullPasses selectedWidth openWork : Nat) : Nat :=
  operationReads widths + fullPasses * selectedWidth + openWork

theorem staged_guard_bound (widths : List Nat) (bound fullPasses selectedWidth openWork : Nat)
    (bounded : ∀ width ∈ widths, width ≤ bound) :
    stagedGuardReads widths fullPasses selectedWidth openWork ≤
      bound * widths.length + fullPasses * selectedWidth + openWork := by
  have localWork := bounded_operation_support widths bound bounded
  unfold stagedGuardReads
  omega

-- A cached directory hit must re-enroll its path observations. Splitting the
-- root/decision/path supports cannot omit negative competing-path lookups.
-- Quint explores when they change; this lemma requires ACTUAL coverage and
-- current observations at this boundary, not a previous successful approval.
theorem candidate_location_support_current
    (required root decision path : List Node) (before now : Node → Nat)
    (coverage : ∀ node, node ∈ required → node ∈ (root ++ decision) ++ path)
    (rootCurrent : ∀ node, node ∈ root → before node = now node)
    (decisionCurrent : ∀ node, node ∈ decision → before node = now node)
    (pathCurrent : ∀ node, node ∈ path → before node = now node) :
    ∀ node, node ∈ required → before node = now node := by
  intro node demanded
  have present := coverage node demanded
  simp only [List.mem_append] at present
  rcases present with (inRoot | inDecision) | inPath
  · exact rootCurrent node inRoot
  · exact decisionCurrent node inDecision
  · exact pathCurrent node inPath

-- The reader already indexes immutable native SDK closures. Registration into
-- its existing source map belongs to the miss, not to every later demand.
-- Fresh source admission is charged separately and never memoized by this law.
def enrollmentWork [DecidableEq Node] (width : Node → Nat) :
    List Node → List Node → Nat
  | [], _ => 0
  | root :: rest, seen =>
      if root ∈ seen then enrollmentWork width rest seen
      else width root + enrollmentWork width rest (root :: seen)

def demandedWork (width : Node → Nat) (roots : List Node) : Nat :=
  (roots.map width).sum

def newlyEnrolled [DecidableEq Node] : List Node → List Node → List Node
  | [], _ => []
  | root :: rest, seen =>
      if root ∈ seen then newlyEnrolled rest seen
      else root :: newlyEnrolled rest (root :: seen)

theorem enrollment_covers_demands [DecidableEq Node] (roots seen : List Node) :
    ∀ root ∈ roots, root ∈ seen ∨ root ∈ newlyEnrolled roots seen := by
  induction roots generalizing seen with
  | nil => simp
  | cons first rest ih =>
    intro root present
    by_cases hit : first ∈ seen
    · simp only [newlyEnrolled, hit, ite_eq_left]
      rcases List.mem_cons.mp present with same | tail
      · exact Or.inl (same ▸ hit)
      · exact ih seen root tail
    · simp only [newlyEnrolled, hit, ite_false]
      rcases List.mem_cons.mp present with same | tail
      · exact Or.inr (List.mem_cons.mpr (Or.inl same))
      · rcases ih (first :: seen) root tail with old | fresh
        · rcases List.mem_cons.mp old with same | old
          · exact Or.inr (List.mem_cons.mpr (Or.inl same))
          · exact Or.inl old
        · exact Or.inr (List.mem_cons_of_mem first fresh)

theorem enrollment_preserves_source_support [DecidableEq Node]
    (closure : Node → List Source) (roots seen : List Node)
    (observations : List Source)
    (old : ∀ root ∈ seen, ∀ source ∈ closure root, source ∈ observations)
    (fresh : ∀ root ∈ newlyEnrolled roots seen,
      ∀ source ∈ closure root, source ∈ observations) :
    ∀ root ∈ roots, ∀ source ∈ closure root, source ∈ observations := by
  intro root demanded source required
  rcases enrollment_covers_demands roots seen root demanded with known | added
  · exact old root known source required
  · exact fresh root added source required

theorem enrollment_bounded_by_demands [DecidableEq Node]
    (width : Node → Nat) (roots seen : List Node) :
    enrollmentWork width roots seen ≤ demandedWork width roots := by
  induction roots generalizing seen with
  | nil => simp [enrollmentWork, demandedWork]
  | cons root rest ih =>
    by_cases hit : root ∈ seen
    · simp only [enrollmentWork, hit, ite_eq_left, demandedWork, List.map_cons, List.sum_cons]
      have h := ih seen
      unfold demandedWork at h
      omega
    · simpa [enrollmentWork, hit, demandedWork] using
        Nat.add_le_add_left (ih (root :: seen)) (width root)

theorem enrolled_repeat_has_no_registration_work [DecidableEq Node]
    (width : Node → Nat) (root : Node) (count : Nat) (seen : List Node)
    (hit : root ∈ seen) :
    enrollmentWork width (List.replicate count root) seen = 0 := by
  induction count with
  | zero => simp [enrollmentWork]
  | succ count ih => simpa [List.replicate_succ, enrollmentWork, hit] using ih

theorem repeated_root_enrolled_once [DecidableEq Node]
    (width : Node → Nat) (root : Node) (count : Nat) :
    enrollmentWork width (List.replicate (count + 1) root) [] = width root := by
  simp only [List.replicate_succ, enrollmentWork, List.not_mem_nil, ite_false]
  rw [enrolled_repeat_has_no_registration_work width root count [root] (by simp)]
  omega

theorem repeated_root_still_admitted_on_every_demand
    (width : Node → Nat) (root : Node) (count : Nat) :
    demandedWork width (List.replicate count root) = count * width root := by
  induction count with
  | zero => simp [demandedWork]
  | succ count ih =>
    simpa [List.replicate_succ, demandedWork, Nat.succ_mul, Nat.add_comm] using
      congrArg (fun n => width root + n) ih

-- DFS vertex/edge work is only ONE term. Native parsing, expansion, repeated
-- token edges (including predicate-internal replay) and GC need independent
-- receipts. No previous source-read bound establishes this weighted budget.

-- Functional abstraction of make-module-interface: its consumer receives the
-- public validator's actual result, never the pre-check constructor candidate.
-- Option models refusal only; this is not a second runtime evidence protocol.
def inspectChecked (check : Value → Option Checked) (candidate : Value)
    (inspect : Checked → Result) : Option Result :=
  (check candidate).map inspect

theorem refused_profile_cannot_reach_inspection
    (check : Value → Option Checked) (candidate : Value)
    (inspect : Checked → Result) (refused : check candidate = none) :
    inspectChecked check candidate inspect = none := by
  simp [inspectChecked, refused]

theorem inspection_receives_actual_checked_profile
    (check : Value → Option Checked) (candidate : Value) (checked : Checked)
    (inspect : Checked → Result) (accepted : check candidate = some checked) :
    inspectChecked check candidate inspect = some (inspect checked) := by
  simp [inspectChecked, accepted]

-- Checked-value normalization need NOT be idempotent. The staged path has one
-- boundary check; retaining the public validated constructor as an implicit
-- default would normalize twice. No arbitrary callback-equivalence is claimed.
theorem normalization_is_not_implicitly_idempotent :
    inspectChecked (fun n : Nat => some (n + 1)) 0 id = some 1 ∧
    inspectChecked (fun n : Nat => some (n + 1)) 1 id = some 2 := by
  decide

-- Pure replay work for a common constructor trace of width k, reached on
-- every boundary. Construction cost and actual per-boundary checking remain
-- independently charged; source bytes and open callbacks are not removed.
theorem constructor_trace_replay_removed (modules boundaries constructor localWidth : Nat) :
    modules * boundaries * (constructor + localWidth) =
      modules * boundaries * localWidth + modules * boundaries * constructor := by
  rw [Nat.mul_add]
  omega

-- Unlike Quint's finite hook schedules, this law quantifies over any returned
-- value and callback. The predicate is assumed to represent the actual return
-- check; neither purity of Scheme observers nor MOP confinement is proved here.
def checkCallbackReturn (valid : Value → Bool) (callback : Value → Value)
    (candidate : Value) : Option Value :=
  let returned := callback candidate
  if valid returned then some returned else none

theorem callback_return_is_checked (valid : Value → Bool)
    (callback : Value → Value) (candidate returned : Value)
    (accepted : checkCallbackReturn valid callback candidate = some returned) :
    valid returned = true := by
  dsimp only [checkCallbackReturn] at accepted
  split at accepted
  next current =>
    have identity := Option.some.inj accepted
    simpa [identity] using current
  next => contradiction

theorem construction_check_cannot_replace_callback_return_check :
    (0 == (0 : Nat)) = true ∧
    checkCallbackReturn (fun n : Nat => n == 0) (fun _ => 1) 0 = none := by
  decide

-- Functional staging, not memoized validation: each demand runs its check.
-- The closed path has no consumer before this check. The open path supplies
-- the actual checked value to the hook, then checks that hook's return anew.
def admitCarrierCandidate (check : Value → Option Value)
    (hook : Option (Value → Value)) (candidate : Value) : Option Value :=
  (check candidate).bind fun checked =>
    match hook with
    | none => some checked
    | some callback => check (callback checked)

theorem closed_carrier_admission_is_one_check
    (check : Value → Option Value) (candidate : Value) :
    admitCarrierCandidate check none candidate = check candidate := by
  simp [admitCarrierCandidate]

theorem refused_carrier_cannot_reach_hook
    (check : Value → Option Value) (candidate : Value) (hook : Value → Value)
    (refused : check candidate = none) :
    admitCarrierCandidate check (some hook) candidate = none := by
  simp [admitCarrierCandidate, refused]

theorem hook_receives_checked_carrier_and_return_is_rechecked
    (check : Value → Option Value) (candidate checked : Value) (hook : Value → Value)
    (accepted : check candidate = some checked) :
    admitCarrierCandidate check (some hook) candidate = check (hook checked) := by
  simp [admitCarrierCandidate, accepted]

-- Only the eliminated recursive-check component is charged. No claim about
-- native read replay, allocation, interpreter expansion or total capacity.
theorem closed_carrier_recursive_check_work (demands width : Nat) :
    demands * (width + width) = demands * width + demands * width := by
  exact Nat.mul_add demands width width

-- Private literal field rows lower to the same left-to-right short circuit.
-- Machine can include a native observer trace and arbitrary getter/predicate
-- effects. Only creation of the static predicate list/cut wrappers is omitted;
-- no purity assumption is made for the actual field operation below.
def evalFieldRows {Key Machine : Type} (step : Key → Machine → Bool × Machine) :
    List Key → Machine → Bool × Machine
  | [], state => (true, state)
  | item :: rest, state =>
    let result := step item state
    if result.1 then evalFieldRows step rest result.2 else result

def lowerFieldRows {Key Machine : Type} (step : Key → Machine → Bool × Machine)
    (keys : List Key) : Machine → Bool × Machine :=
  keys.foldr (fun item next state =>
    let result := step item state
    if result.1 then next result.2 else result) (fun state => (true, state))

theorem lowering_preserves_effectful_field_order {Key Machine : Type}
    (step : Key → Machine → Bool × Machine) (keys : List Key) :
    lowerFieldRows step keys = evalFieldRows step keys := by
  induction keys with
  | nil => rfl
  | cons item rest ih =>
    funext state
    change (let result := step item state
            if result.1 then lowerFieldRows step rest result.2 else result) = _
    rw [ih]
    rfl

structure DeclarationCost where
  preparation : Nat
  expansion : Nat
  initialization : Nat
  admission : Nat
  replay : Nat
  sourceGuards : Nat
  collection : Nat

def DeclarationCost.total (cost : DeclarationCost) : Nat :=
  cost.preparation + cost.expansion + cost.initialization + cost.admission +
    cost.replay + cost.sourceGuards + cost.collection

theorem linear_work_does_not_establish_capacity :
    1000 * 700000 > 600000000 := by decide
-- Above is a counterexample in abstract microsecond charges, NOT a measured
-- machine-time claim. Even linear 0.7-second declarations exceed 600 seconds.

end YuanxuProof.ModuleSystem.Graph.SourceClosureWork
