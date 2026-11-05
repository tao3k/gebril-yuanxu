-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Loading.IncrementalRoles

namespace YuanxuProof.ModuleSystem.Loading.DependencyPublication
open Graph.TestAdmission IncrementalRoles

/-- A single immutable publication contains both directions of the dependency
view and its certificate slots. The runtime correspondence must install this
view atomically. Functions model point lookups in existing POO structures. -/
structure Bundle where
  certificate : Nat → Option Nat
  dependencies : Nat → List Nat
  consumers : Nat → List Nat

def Bundle.Exact (bundle : Bundle) : Prop :=
  ∀ provider consumer, consumer ∈ bundle.consumers provider ↔
    provider ∈ bundle.dependencies consumer

inductive Phase where
  | ready
  | fencing (changed : List Nat)
  | resuming (previous added : List Nat) (sealed : IndexedDiscovery)
  | restricted (changed : List Nat) (reverse : IndexedDiscovery)

structure State where
  ticket : Nat
  bundle : Bundle
  phase : Phase

/-- Runtime correspondence issues these observations for this exact base
and candidate. The model has no operation that retargets them. -/
structure AdmissionEvidence (_base : State) (_replacement : Bundle) where
  verify : Nat → Bool
  entryOK : Bool
  returnOK : Bool

/-- Admission inputs belong to the captured sealed state and the exact
replacement bundle. The verdict is derived from these inputs, not passed
as an independent Boolean at commit time. -/
structure Staged where
  base : State
  replacement : Bundle
  exactRegistration : replacement.Exact
  requested : List Nat
  fuel : Nat
  known : Nat → Bool
  evidence : AdmissionEvidence base replacement

def Staged.forward (staged : Staged) (reverse : IndexedDiscovery) : IndexedDiscovery :=
  let retained := fun owner => (staged.base.bundle.certificate owner).isSome
  let reusable := fun owner => retained owner && !reverse.visited.contains owner
  discoverIndexed (editDependencies staged.replacement.dependencies reusable) staged.fuel
    ⟨⟨[], editRoots reverse retained staged.requested⟩, ∅⟩

def Staged.approved (staged : Staged) : Bool :=
  match staged.base.phase with
  | .restricted _ reverse =>
    let reusable := fun owner =>
      (staged.base.bundle.certificate owner).isSome && !reverse.visited.contains owner
    publishDependencyEdit reverse (staged.forward reverse) reusable
      (fun owner => staged.known owner && (staged.replacement.certificate owner).isSome)
      staged.evidence.verify staged.evidence.entryOK staged.evidence.returnOK
  | _ => false

theorem staged_approval_requires_both_effect_checks (staged : Staged)
    (approved : staged.approved = true) :
    staged.evidence.entryOK = true ∧ staged.evidence.returnOK = true := by
  cases phase : staged.base.phase with
  | ready => simp [Staged.approved, phase] at approved
  | fencing changed => simp [Staged.approved, phase] at approved
  | resuming previous added sealed => simp [Staged.approved, phase] at approved
  | restricted changed reverse =>
    simp only [Staged.approved, phase] at approved
    have checks := dependency_edit_publication_checks _ _ _ _ _ _ _ approved
    exact ⟨checks.1, checks.2.1⟩

/-- Resume only within one immutable old registration. The completed
membership and ordered trace are reused. Only new roots are queued. -/
def resumeReverse (consumers : Nat → List Nat) (sealed : IndexedDiscovery)
    (added : List Nat) (fuel : Nat) : IndexedDiscovery :=
  discoverIndexed consumers fuel { sealed with ordered := ⟨sealed.ordered.seen, added⟩ }

inductive Edit where
  | begin (changed : List Nat)
  | seal (expected fuel : Nat)
  | commit (staged : Staged)

/-- Commands linearize at the state cell. Expensive work may be staged outside
it, but seal and commit are conditional on the captured state ticket.
A failed commit leaves the restriction in place, allowing a retry of this edit. -/
def step (state : State) (command : Edit) : State :=
  match command, state.phase with
  | .begin changed, .ready =>
    ⟨state.ticket + 1, state.bundle, .fencing changed⟩
  | .begin changed, .fencing pending =>
    ⟨state.ticket + 1, state.bundle, .fencing (pending ++ changed)⟩
  | .begin changed, .restricted previous sealed =>
    ⟨state.ticket + 1, state.bundle, .resuming previous changed sealed⟩
  | .begin changed, .resuming previous added sealed =>
    ⟨state.ticket + 1, state.bundle, .resuming previous (added ++ changed) sealed⟩
  | .seal expected fuel, .fencing changed =>
    let reverse := discoverIndexed state.bundle.consumers fuel ⟨⟨[], changed⟩, ∅⟩
    if expected == state.ticket && reverse.ordered.pending.isEmpty then
      ⟨state.ticket + 1, state.bundle, .restricted changed reverse⟩
    else state
  | .seal expected fuel, .resuming previous added sealed =>
    let reverse := resumeReverse state.bundle.consumers sealed added fuel
    if expected == state.ticket && reverse.ordered.pending.isEmpty then
      ⟨state.ticket + 1, state.bundle, .restricted (previous ++ added) reverse⟩
    else state
  | .commit staged, .restricted _ _ =>
    if staged.base.ticket == state.ticket && staged.approved then
      ⟨state.ticket + 1, staged.replacement, .ready⟩
    else state
  | _, _ => state

theorem step_same_or_new_ticket (state : State) (edit : Edit) :
    step state edit = state ∨ state.ticket < (step state edit).ticket := by
  cases edit <;> cases phase : state.phase <;> simp only [step, phase]
  all_goals try (exact Or.inl trivial)
  all_goals try (exact Or.inr (Nat.lt_succ_self _))
  all_goals split <;> simp

def run (state : State) (edits : List Edit) : State := edits.foldl step state

theorem run_ticket_monotone (state : State) (edits : List Edit) :
    state.ticket ≤ (run state edits).ticket := by
  induction edits generalizing state with
  | nil => exact Nat.le_refl _
  | cons edit tail ih =>
    change state.ticket ≤ (run (step state edit) tail).ticket
    rcases step_same_or_new_ticket state edit with same | advanced
    · rw [same]; exact ih state
    · exact Nat.le_trans (Nat.le_of_lt advanced) (ih _)

theorem run_same_ticket_same_view (state : State) (edits : List Edit)
    (same : (run state edits).ticket = state.ticket) : run state edits = state := by
  induction edits generalizing state with
  | nil => rfl
  | cons edit tail ih =>
    change (run (step state edit) tail).ticket = state.ticket at same
    change run (step state edit) tail = state
    rcases step_same_or_new_ticket state edit with noop | advanced
    · rw [noop] at same ⊢
      exact ih state same
    · have ordered := run_ticket_monotone (step state edit) tail
      omega

def State.readable (state : State) (owner : Nat) : Bool :=
  match state.phase with
  | .ready => true
  | .fencing _ | .resuming _ _ _ => false
  | .restricted _ reverse => !reverse.visited.contains owner

/-- Both index and certificate originate from the same captured view.
The caller must finish before releasing anything across the effect boundary. -/
def read (snapshot live : State) (owner : Nat) (entryOK returnOK : Bool) :
    Option (Nat × List Nat) :=
  if entryOK && snapshot.readable owner && (snapshot.ticket == live.ticket) && returnOK then
    (snapshot.bundle.certificate owner).map fun cert => (cert, snapshot.bundle.consumers owner)
  else none

theorem concurrent_read_has_one_view (snapshot : State) (edits : List Edit) (owner cert : Nat)
    (consumers : List Nat) (entryOK returnOK : Bool)
    (served : read snapshot (run snapshot edits) owner entryOK returnOK = some (cert, consumers)) :
    entryOK = true ∧ returnOK = true ∧
      (run snapshot edits).bundle.certificate owner = some cert ∧
      (run snapshot edits).bundle.consumers owner = consumers := by
  unfold read at served
  split at served
  next guard =>
    simp only [Bool.and_eq_true, beq_iff_eq] at guard
    have same := run_same_ticket_same_view snapshot edits guard.1.2.symm
    rw [same]
    cases h : snapshot.bundle.certificate owner with
    | none => simp [h] at served
    | some value =>
      simp [h] at served
      exact ⟨guard.1.1.1, guard.2, congrArg some served.1, served.2⟩
  next => contradiction

theorem failed_commit_keeps_fence (state : State) (staged : Staged)
    (failed : staged.approved = false) :
    step state (.commit staged) = state := by
  cases phase : state.phase <;> simp [step, phase, failed]

theorem successful_commit_switches_both (state : State) (changed : List Nat)
    (reverse : IndexedDiscovery) (phase : state.phase = .restricted changed reverse)
    (staged : Staged) (ticket : staged.base.ticket = state.ticket)
    (approved : staged.approved = true) :
    let result := step state (.commit staged)
    result.bundle = staged.replacement ∧ result.bundle.Exact ∧ result.ticket = state.ticket + 1 := by
  simp [step, phase, ticket, approved, staged.exactRegistration]

theorem seal_keeps_old_bundle (state : State) (expected fuel : Nat) :
    (step state (.seal expected fuel)).bundle = state.bundle := by
  cases phase : state.phase <;> simp only [step, phase]
  all_goals split <;> rfl

theorem stale_commit_is_noop (state : State) (staged : Staged)
    (stale : staged.base.ticket ≠ state.ticket) :
    step state (.commit staged) = state := by
  cases phase : state.phase <;> simp [step, phase, stale]

theorem seal_blocks_old_affected (state : State) (changed : List Nat)
    (phase : state.phase = .fencing changed) (fuel owner : Nat)
    (exact : state.bundle.Exact)
    (dirty : Affected (fun consumer provider => provider ∈ state.bundle.dependencies consumer)
      (fun k => k ∈ changed) owner) :
    (step state (.seal state.ticket fuel)).readable owner = false := by
  let reverse := discoverIndexed state.bundle.consumers fuel ⟨⟨[], changed⟩, ∅⟩
  have blocked := old_index_blocks_affected_certificate state.bundle.consumers
    (fun consumer provider => provider ∈ state.bundle.dependencies consumer)
    exact changed fuel owner true dirty
  change oldCertificateUsable reverse.ordered.pending.isEmpty
    (reverse.visited.contains owner) true = false at blocked
  by_cases complete : reverse.ordered.pending = []
  · simpa [step, phase, State.readable, ← show reverse =
      discoverIndexed state.bundle.consumers fuel ⟨⟨[], changed⟩, ∅⟩ from rfl,
      complete, oldCertificateUsable] using blocked
  · simp [step, phase, State.readable, ← show reverse =
      discoverIndexed state.bundle.consumers fuel ⟨⟨[], changed⟩, ∅⟩ from rfl, complete]

theorem failed_replacement_cannot_restore_affected (state : State) (changed : List Nat)
    (phase : state.phase = .fencing changed) (fuel owner : Nat)
    (exact : state.bundle.Exact)
    (dirty : Affected (fun consumer provider => provider ∈ state.bundle.dependencies consumer)
      (fun k => k ∈ changed) owner) (staged : Staged) (failed : staged.approved = false) :
    (step (step state (.seal state.ticket fuel)) (.commit staged)).readable owner = false := by
  rw [failed_commit_keeps_fence _ _ failed]
  exact seal_blocks_old_affected state changed phase fuel owner exact dirty

theorem merged_changes_exact (registered : Nat → Nat → Prop)
    (first second : List Nat) (owner : Nat) :
    Affected registered (fun k => k ∈ first ++ second) owner ↔
      Affected registered (fun k => k ∈ first) owner ∨
      Affected registered (fun k => k ∈ second) owner := by
  constructor
  · intro dirty
    induction dirty with
    | source member =>
      exact (List.mem_append.mp member).elim (fun h => Or.inl (.source h)) (fun h => Or.inr (.source h))
    | consumer edge _ ih =>
      exact ih.elim (fun h => Or.inl (.consumer edge h)) (fun h => Or.inr (.consumer edge h))
  · have lift (roots : List Nat) (included : ∀ k ∈ roots, k ∈ first ++ second)
        (dirty : Affected registered (fun k => k ∈ roots) owner) :
        Affected registered (fun k => k ∈ first ++ second) owner := by
      induction dirty with
      | source member => exact .source (included _ member)
      | consumer edge _ ih => exact .consumer edge ih
    exact fun dirty => dirty.elim
      (lift first (fun _ h => List.mem_append_left _ h))
      (lift second (fun _ h => List.mem_append_right _ h))

theorem merge_rejects_staged_even_after_more_steps (staged : Staged) (state : State)
    (first second : List Nat) (reverse : IndexedDiscovery)
    (phase : state.phase = .restricted first reverse)
    (captured : staged.base.ticket = state.ticket) (edits : List Edit) :
    let live := run (step state (.begin second)) edits
    step live (.commit staged) = live := by
  have advanced : (step state (.begin second)).ticket = state.ticket + 1 := by simp [step, phase]
  have later := run_ticket_monotone (step state (.begin second)) edits
  apply stale_commit_is_noop
  omega

theorem commit_binds_captured_admission (staged : Staged) (edits : List Edit)
    (installed : (step (run staged.base edits) (.commit staged)).ticket ≠
      (run staged.base edits).ticket) :
    run staged.base edits = staged.base ∧ staged.approved = true ∧
      (step (run staged.base edits) (.commit staged)).bundle = staged.replacement ∧
      staged.replacement.Exact := by
  by_cases ticket : staged.base.ticket = (run staged.base edits).ticket
  · have same := run_same_ticket_same_view staged.base edits ticket.symm
    by_cases approved : staged.approved = true
    · refine ⟨same, approved, ?_, staged.exactRegistration⟩
      cases phase : (run staged.base edits).phase with
      | ready => exact False.elim (installed (by simp [step, phase]))
      | fencing changed => exact False.elim (installed (by simp [step, phase]))
      | resuming previous added sealed => exact False.elim (installed (by simp [step, phase]))
      | restricted changed reverse => simp [step, phase, ticket, approved]
    · have failed : staged.approved = false := by
        cases h : staged.approved <;> simp_all
      exact False.elim (installed (congrArg State.ticket (failed_commit_keeps_fence _ _ failed)))
  · exact False.elim (installed (congrArg State.ticket (stale_commit_is_noop _ _ ticket)))

/-- The next invalidation begins from the installed registration. The old
bundle is no longer in the active cell, even if a reader still holds it. -/
theorem next_edit_uses_replacement_index (staged : Staged) (edits : List Edit)
    (installed : (step (run staged.base edits) (.commit staged)).ticket ≠
      (run staged.base edits).ticket) (changed : List Nat) (provider : Nat) :
    (step (step (run staged.base edits) (.commit staged)) (.begin changed)).bundle.consumers
      provider = staged.replacement.consumers provider := by
  have keeps (state : State) : (step state (.begin changed)).bundle = state.bundle := by
    cases phase : state.phase <;> simp [step, phase]
  rw [keeps, (commit_binds_captured_admission staged edits installed).2.2.1]

theorem resumed_reverse_exact (consumers : Nat → List Nat) (first added : List Nat)
    (sealed : IndexedDiscovery) (newFuel : Nat)
    (exactIndex : sealed.Exact)
    (old : ∀ k, k ∈ sealed.ordered.seen ↔ Demanded consumers first k)
    (complete : (resumeReverse consumers sealed added newFuel).ordered.pending = [])
    (owner : Nat) :
    owner ∈ (resumeReverse consumers sealed added newFuel).ordered.seen ↔
      Demanded consumers (first ++ added) owner := by
  let seed : IndexedDiscovery := { sealed with ordered := ⟨sealed.ordered.seen, added⟩ }
  have index : seed.Exact := exactIndex
  have same := discover_indexed_refines consumers newFuel seed index
  change (discoverIndexed consumers newFuel seed).ordered.pending = [] at complete
  rw [same] at complete
  change owner ∈ (discoverIndexed consumers newFuel seed).ordered.seen ↔ _
  rw [same]
  have closed : ∀ k, Demanded consumers (first ++ added) k →
      ∀ child ∈ consumers k, Demanded consumers (first ++ added) child :=
    fun k reached child edge => .dependency k child reached edge
  have inside : Inside (Demanded consumers (first ++ added)) seed.ordered := by
    constructor
    · intro k member
      have reached := (old k).mp member
      clear member
      induction reached with
      | root k root => exact .root k (List.mem_append_left _ root)
      | dependency parent child _ edge ih => exact .dependency parent child ih edge
    · exact fun k member => .root k (List.mem_append_right _ member)
  have covers : Covers consumers (first ++ added) seed.ordered := by
    constructor
    · intro k member
      exact (List.mem_append.mp member).elim
        (fun h => Or.inl ((old k).mpr (.root k h))) Or.inr
    · intro k member child edge
      exact Or.inl ((old child).mpr (.dependency k child ((old k).mp member) edge))
  have finalCovers := discover_preserves_coverage consumers (first ++ added) newFuel _ covers
  constructor
  · exact (discover_stays_inside consumers _ closed newFuel _ inside).1 owner
  · intro reached
    have finish : ∀ k, Scheduled (discover consumers newFuel seed.ordered) k →
        k ∈ (discover consumers newFuel seed.ordered).seen := by
      intro k h
      simpa [Scheduled, complete] using h
    induction reached with
    | root k member => exact finish k (finalCovers.1 k member)
    | dependency parent child _ edge ih => exact finish child (finalCovers.2 parent ih child edge)

/-- The actual begin/seal transition installs the resumed result, with
exactly the same membership as any completed restart from all roots. -/
theorem reseal_after_merge_matches_restart (state : State) (first added : List Nat)
    (sealed : IndexedDiscovery) (phase : state.phase = .restricted first sealed)
    (index : sealed.Exact)
    (old : ∀ k, k ∈ sealed.ordered.seen ↔ Demanded state.bundle.consumers first k)
    (resumeFuel restartFuel owner : Nat)
    (complete : (resumeReverse state.bundle.consumers sealed added resumeFuel).ordered.pending = [])
    (restart : (discoverIndexed state.bundle.consumers restartFuel
      ⟨⟨[], first ++ added⟩, ∅⟩).ordered.pending = []) :
    let merged := step state (.begin added)
    let live := step merged (.seal merged.ticket resumeFuel)
    ∃ reverse, live.phase = .restricted (first ++ added) reverse ∧
      reverse.Exact ∧
      (owner ∈ reverse.ordered.seen ↔ owner ∈ (discoverIndexed state.bundle.consumers
        restartFuel ⟨⟨[], first ++ added⟩, ∅⟩).ordered.seen) := by
  refine ⟨resumeReverse state.bundle.consumers sealed added resumeFuel, ?_, ?_, ?_⟩
  · simp [step, phase, complete]
  · exact discover_indexed_keeps_exact _ _ _ index
  · rw [resumed_reverse_exact _ first added sealed resumeFuel index old complete,
      completed_indexed_discovery_exact _ _ restartFuel restart]

private def edgeBundle (certificate : Nat → Option Nat) (edges : List (Nat × Nat)) : Bundle :=
  ⟨certificate,
    fun consumer => (edges.filter (fun edge => edge.1 == consumer)).map Prod.snd,
    fun provider => (edges.filter (fun edge => edge.2 == provider)).map Prod.fst⟩

private theorem edgeBundle_exact (certificate : Nat → Option Nat) (edges : List (Nat × Nat)) :
    (edgeBundle certificate edges).Exact := by
  intro provider consumer
  simp only [edgeBundle, List.mem_map, List.mem_filter, beq_iff_eq]
  exact ⟨fun ⟨edge, ⟨member, p⟩, c⟩ => ⟨edge, ⟨member, c⟩, p⟩,
    fun ⟨edge, ⟨member, c⟩, p⟩ => ⟨edge, ⟨member, p⟩, c⟩⟩

/-- Two disjoint local changes arrive against one 10,000-owner directory.
The second edit arrives after the first has sealed and staged admission. -/
private def mergedEditScale : Bool :=
  let cert := fun owner => if owner < 10000 && owner != 9000 && owner != 9001 then some 1 else none
  let old := edgeBundle cert [(11, 10), (12, 11), (21, 20), (22, 21)]
  let initial : State := ⟨0, old, .ready⟩
  let first := step (step initial (.begin [11])) (.seal 1 2)
  let stage := fun base edges verify =>
    let updated := fun owner => if owner < 10000 then some 2 else none
    ({
      base := base
      replacement := edgeBundle updated edges
      exactRegistration := edgeBundle_exact _ _
      requested := []
      fuel := 8
      known := (· < 10000)
      evidence := ⟨verify, true, true⟩
    } : Staged)
  let obsolete := stage first [(11, 9000), (12, 11), (21, 20), (22, 21)] (fun _ => true)
  let merged := step first (.begin [21])
  let sealed := step merged (.seal merged.ticket 2)
  let next := stage sealed [(11, 9000), (12, 11), (21, 9001), (22, 21)] (fun _ => true)
  let rejected := { next with evidence := ⟨(· != 9001), true, true⟩ }
  let badReturn := { next with evidence := ⟨(fun _ => true), true, false⟩ }
  let stale := step sealed (.commit obsolete)
  let failed := step sealed (.commit rejected)
  let committed := step sealed (.commit next)
  match sealed.phase with
  | .restricted changed reverse =>
    let restart := discoverIndexed old.consumers 4 ⟨⟨[], [11, 21]⟩, ∅⟩
    let shortRestart := discoverIndexed old.consumers 2 ⟨⟨[], [11, 21]⟩, ∅⟩
    changed == [11, 21] && reverse.ordered.seen == [22, 21, 12, 11] &&
      restart.ordered.pending.isEmpty && restart.ordered.seen == reverse.ordered.seen &&
      !shortRestart.ordered.pending.isEmpty &&
      (next.forward reverse).ordered.seen == [9000, 11, 12, 9001, 21, 22] &&
      obsolete.approved && stale.ticket == sealed.ticket &&
      !rejected.approved && !badReturn.approved && failed.ticket == sealed.ticket &&
      read sealed failed 12 true true == none &&
      read sealed failed 22 true true == none &&
      read sealed failed 10 true true == some (1, [11]) &&
      read first merged 20 true true == none &&
      read sealed committed 10 true true == none &&
      read committed committed 9000 true true == some (2, [11]) &&
      read committed committed 9001 true true == some (2, [21]) &&
      (step committed (.begin [10])).bundle.consumers 10 == []
  | _ => false

#guard mergedEditScale

end YuanxuProof.ModuleSystem.Loading.DependencyPublication
