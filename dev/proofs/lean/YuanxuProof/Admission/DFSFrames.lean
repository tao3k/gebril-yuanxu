-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.IdentityDFS

/-! Native recursive for-each frames refine the DFS pending-stack projection.
Empty-frame returns stutter; each new identity is marked before its children.
This correspondence excludes callbacks changing the dependency graph. -/
namespace YuanxuProof.Admission.DFSFrames
open IdentityDFS

def quintSourceDigest : String := IdentityDFS.quintSourceDigest

structure Frames where
  frames : List (List Nat)
  seen : Std.HashSet Nat
  order : List Nat

def flatten (s : Frames) : State := ⟨s.frames.flatten, s.seen, s.order⟩

def advance (edges : Edges) (s : Frames) : Frames :=
  match s.frames with
  | [] => s
  | [] :: rest => { s with frames := rest }
  | (id :: tail) :: rest =>
    if s.seen.contains id then { s with frames := tail :: rest }
    else ⟨edges id :: tail :: rest, s.seen.insert id, s.order ++ [id]⟩

theorem return_stutters (rest : List (List Nat)) (seen : Std.HashSet Nat) (order : List Nat) :
    flatten (advance edges ⟨[] :: rest, seen, order⟩) = flatten ⟨[] :: rest, seen, order⟩ := by
  simp [advance, flatten]

/-- Entering a node, or skipping a shared identity, is exactly one work-stack
step. Dependencies precede siblings; no BFS substitution/reordering occurs. -/
theorem enter_refines (edges : Edges) (id : Nat) (tail : List Nat)
    (rest : List (List Nat)) (seen : Std.HashSet Nat) (order : List Nat) :
    flatten (advance edges ⟨(id :: tail) :: rest, seen, order⟩) =
      step edges (flatten ⟨(id :: tail) :: rest, seen, order⟩) := by
  by_cases visited : seen.contains id <;> simp [advance, flatten, step, visited ]

def frameMeasure (vertices : List Nat) (edges : Edges) (s : Frames) : Nat :=
  2 * measure vertices edges (flatten s) + s.frames.length

theorem frame_decreases (within : Within vertices (flatten s)) (nonempty : s.frames ≠ []) :
    frameMeasure vertices edges (advance edges s) < frameMeasure vertices edges s := by
  cases s with
  | mk frames seen order =>
    cases frames with
    | nil => exact False.elim (nonempty rfl)
    | cons first rest =>
      cases first with
      | nil => simp [frameMeasure, advance, flatten]
      | cons id tail =>
        have decrease := measure_decreases (edges := edges) within (by simp [flatten])
        rw [← enter_refines edges id tail rest seen order] at decrease
        have count : (advance edges ⟨(id :: tail) :: rest, seen, order⟩).frames.length ≤
            ((id :: tail) :: rest).length + 1 := by
          by_cases visited : seen.contains id <;> simp [advance, visited]
        change (advance edges ⟨(id :: tail) :: rest, seen, order⟩).frames.length ≤
          rest.length + 2 at count
        change 2 * measure vertices edges (flatten (advance edges ⟨(id :: tail) :: rest, seen, order⟩)) +
            (advance edges ⟨(id :: tail) :: rest, seen, order⟩).frames.length <
          2 * measure vertices edges (flatten ⟨(id :: tail) :: rest, seen, order⟩) + (rest.length + 1)
        omega

theorem frame_within (closed : Closed vertices edges) (within : Within vertices (flatten s)) :
    Within vertices (flatten (advance edges s)) := by
  cases s with
  | mk frames seen order =>
    cases frames with
    | nil => exact within
    | cons first rest =>
      cases first with
      | nil => simpa [advance, flatten] using within
      | cons id tail => rw [enter_refines]; exact step_within closed within

def execute (edges : Edges) : Nat → Frames → Frames
  | 0, s => s
  | fuel + 1, s =>
    match s.frames with
    | [] => s
    | _ :: _ => execute edges fuel (advance edges s)

theorem frames_drain (closed : Closed vertices edges) (within : Within vertices (flatten s))
    (budget : frameMeasure vertices edges s ≤ fuel) :
    (execute edges fuel s).frames = [] := by
  induction fuel generalizing s with
  | zero =>
    have empty : s.frames = [] := List.length_eq_zero_iff.mp (by unfold frameMeasure at budget; omega)
    simpa [execute] using empty
  | succ fuel ih =>
    cases pending : s.frames with
    | nil => simp [execute, pending]
    | cons first rest =>
      have decrease := frame_decreases (edges := edges) within (by simp [pending])
      simpa [execute, pending] using ih (frame_within closed within) (by omega)

theorem advance_invariant (valid : Invariant edges roots (flatten s)) :
    Invariant edges roots (flatten (advance edges s)) := by
  cases s with
  | mk frames seen order =>
    cases frames with
    | nil => exact valid
    | cons first rest =>
      cases first with
      | nil => simpa [advance, flatten] using valid
      | cons id tail => rw [enter_refines]; exact step_invariant valid

theorem execute_invariant (valid : Invariant edges roots (flatten s)) :
    Invariant edges roots (flatten (execute edges fuel s)) := by
  induction fuel generalizing s with
  | zero => exact valid
  | succ fuel ih =>
    cases pending : s.frames with
    | nil => simpa [execute, pending] using valid
    | cons first rest => simpa [execute, pending] using ih (advance_invariant valid)

def start (roots : List Nat) : Frames := ⟨[roots], {}, []⟩

def replay (vertices : List Nat) (edges : Edges) (roots : List Nat) : Frames :=
  execute edges (frameMeasure vertices edges (start roots)) (start roots)

theorem replay_drains (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) :
    (replay vertices edges roots).frames = [] := by
  apply frames_drain closed
  · simpa [flatten, start, Within] using rootsWithin
  · exact Nat.le_refl _

theorem replay_invariant : Invariant edges roots (flatten (replay vertices edges roots)) := by
  apply execute_invariant
  simpa [flatten, start, initial] using initial_invariant edges roots

theorem replay_nodup : (replay vertices edges roots).order.Nodup :=
  replay_invariant.unique

theorem replay_exact (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) (id : Nat) :
    id ∈ (replay vertices edges roots).order ↔ Reached edges roots id := by
  have valid := replay_invariant (vertices := vertices) (edges := edges) (roots := roots)
  have drained := replay_drains closed rootsWithin
  constructor
  · intro member; exact valid.sound id (.inr member)
  · intro reached
    induction reached with
    | root member =>
      have covered := valid.rootsCovered _ member
      simpa [flatten, drained] using covered
    | dependency parent member ih =>
      have covered := valid.closed _ ih _ member
      simpa [flatten, drained] using covered

theorem final_covers_frames (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) (order : List Nat)
    (enumeration : order.Perm (replay vertices edges roots).order)
    (recorded current : Nat → ReplayBoundary.Binding) (world : SourceWindows.World)
    (accepted : ReplayBoundary.firstIssue (finalOps order recorded current) world = none)
    (id : Nat) (reached : Reached edges roots id) : recorded id = current id := by
  have member := (replay_exact closed rootsWithin id).mpr reached
  exact (final_check_exact order recorded current world).mp accepted id
    (enumeration.mem_iff.mpr member)

end YuanxuProof.Admission.DFSFrames
