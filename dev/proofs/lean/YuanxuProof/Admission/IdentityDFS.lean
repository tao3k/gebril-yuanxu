-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReplayBoundary
import LeanPoo.C4.ReachabilityInvariant
import Std.Data.HashSet.Lemmas

/-! DFS specialization of LeanPoo's pending/unseen-weight reachability argument.
Unlike its BFS, dependencies precede pending siblings, matching native replay.
IDs project read-record reference identity, NEVER payload/slot/source equality.
The graph is finite and fixed; callback graph growth is not certified here. -/
namespace YuanxuProof.Admission.IdentityDFS
open ReplayBoundary SourceWindows

def quintSourceDigest : String :=
  "sha256:3f8636bb3201249eb33fa751063ed2fd6c02c2f52481dc755bd84aab5e191586"

abbrev Edges := Nat → List Nat
structure State where
  pending : List Nat
  seen : Std.HashSet Nat
  order : List Nat

def step (edges : Edges) (s : State) : State :=
  match s.pending with
  | [] => s
  | id :: rest =>
    if s.seen.contains id then { s with pending := rest }
    else ⟨edges id ++ rest, s.seen.insert id, s.order ++ [id]⟩

def walk (edges : Edges) : Nat → State → State
  | 0, s => s
  | fuel + 1, s =>
    match s.pending with
    | [] => s
    | _ :: _ => walk edges fuel (step edges s)

-- Same decreasing potential as LeanPoo C4, specialized to the DFS work stack.
def unseenWeight (vertices : List Nat) (edges : Edges) (seen : Std.HashSet Nat) : Nat :=
  (vertices.map fun id => if seen.contains id then 0 else (edges id).length).sum

theorem weight_insert_le (vertices : List Nat) (edges : Edges)
    (seen : Std.HashSet Nat) (id : Nat) :
    unseenWeight vertices edges (seen.insert id) ≤ unseenWeight vertices edges seen := by
  induction vertices with
  | nil => simp [unseenWeight]
  | cons first rest ih =>
    by_cases same : id = first <;> by_cases visited : seen.contains first <;>
      simp [unseenWeight, Std.HashSet.contains_insert, same, visited] at * <;> omega

theorem weight_insert_consumes (vertices : List Nat) (edges : Edges)
    (seen : Std.HashSet Nat) (id : Nat) (member : id ∈ vertices)
    (absent : seen.contains id = false) :
    unseenWeight vertices edges (seen.insert id) + (edges id).length ≤
      unseenWeight vertices edges seen := by
  induction vertices with
  | nil => simp at member
  | cons first rest ih =>
    rcases List.mem_cons.mp member with same | later
    · subst first
      have bound := weight_insert_le rest edges seen id
      change (if (seen.insert id).contains id then 0 else (edges id).length) +
        unseenWeight rest edges (seen.insert id) + (edges id).length ≤
        (if seen.contains id then 0 else (edges id).length) + unseenWeight rest edges seen
      simp only [Std.HashSet.contains_insert, BEq.rfl, Bool.true_or, absent,
        Bool.false_eq_true, ↓reduceIte]
      omega
    · have bound := ih later
      by_cases same : id = first <;> by_cases visited : seen.contains first <;>
        simp [unseenWeight, Std.HashSet.contains_insert, same, visited] at * <;> omega

def measure (vertices : List Nat) (edges : Edges) (s : State) : Nat :=
  s.pending.length + unseenWeight vertices edges s.seen

def Within (vertices : List Nat) (s : State) : Prop :=
  ∀ id ∈ s.pending, id ∈ vertices

def Closed (vertices : List Nat) (edges : Edges) : Prop :=
  ∀ id ∈ vertices, ∀ child ∈ edges id, child ∈ vertices

theorem step_within (closed : Closed vertices edges) (within : Within vertices s) :
    Within vertices (step edges s) := by
  cases s with
  | mk pending seen order =>
    cases pending with
    | nil => exact within
    | cons id rest =>
      by_cases visited : seen.contains id
      · simpa [step, visited, Within] using
          (fun child (member : child ∈ rest) => within child (by simp [member]))
      · intro child member
        simp only [step, visited, Bool.false_eq_true, ↓reduceIte, List.mem_append] at member
        rcases member with dependency | sibling
        · exact closed id (within id (by simp)) child dependency
        · exact within child (by simp [sibling])

theorem measure_decreases (within : Within vertices s) (nonempty : s.pending ≠ []) :
    measure vertices edges (step edges s) < measure vertices edges s := by
  cases s with
  | mk pending seen order =>
    cases pending with
    | nil => exact False.elim (nonempty rfl)
    | cons id rest =>
      by_cases visited : seen.contains id
      · simp [measure, step, visited]
      · have absent : seen.contains id = false := Bool.eq_false_iff.mpr visited
        have member := within id (by simp)
        have consumes := weight_insert_consumes vertices edges seen id member absent
        simp [measure, step, visited]
        omega

/-- No arbitrary runtime fuel limit: the finite structural potential proves
exhaustion, including duplicate edges, self loops and larger cycles. -/
theorem walk_drains (closed : Closed vertices edges) (within : Within vertices s)
    (budget : measure vertices edges s ≤ fuel) :
    (walk edges fuel s).pending = [] := by
  induction fuel generalizing s with
  | zero =>
    have empty : s.pending = [] := List.length_eq_zero_iff.mp (by unfold measure at budget; omega)
    simpa [walk] using empty
  | succ fuel ih =>
    cases pending : s.pending with
    | nil => simp [walk, pending]
    | cons id rest =>
      have decrease := measure_decreases (edges := edges) within (by simp [pending])
      simpa [walk, pending] using ih (step_within closed within) (by omega)

inductive Reached (edges : Edges) (roots : List Nat) : Nat → Prop where
  | root {id : Nat} (member : id ∈ roots) : Reached edges roots id
  | dependency {id child : Nat} (parent : Reached edges roots id) (member : child ∈ edges id) :
      Reached edges roots child

structure Invariant (edges : Edges) (roots : List Nat) (s : State) : Prop where
  membership : ∀ id, s.seen.contains id = true ↔ id ∈ s.order
  unique : s.order.Nodup
  rootsCovered : ∀ id ∈ roots, id ∈ s.pending ∨ id ∈ s.order
  closed : ∀ id ∈ s.order, ∀ child ∈ edges id, child ∈ s.pending ∨ child ∈ s.order
  sound : ∀ id, id ∈ s.pending ∨ id ∈ s.order → Reached edges roots id

private theorem move_membership (id item : Nat) (rest order extras : List Nat)
    (member : item ∈ id :: rest ∨ item ∈ order) :
    item ∈ extras ++ rest ∨ item ∈ order ++ [id] := by
  rcases member with queued | stored
  · rcases List.mem_cons.mp queued with same | later
    · subst item; exact .inr (by simp)
    · exact .inl (List.mem_append_right _ later)
  · exact .inr (List.mem_append_left _ stored)

theorem step_invariant (valid : Invariant edges roots s) :
    Invariant edges roots (step edges s) := by
  cases s with
  | mk pending seen order =>
    cases pending with
    | nil => exact valid
    | cons id rest =>
      by_cases visited : seen.contains id
      · have stored := (valid.membership id).mp visited
        simp only [step, visited, ↓reduceIte]
        refine ⟨valid.membership, valid.unique, ?_, ?_, ?_⟩
        · intro item member
          rcases valid.rootsCovered item member with queued | done
          · rcases List.mem_cons.mp queued with same | later
            · exact .inr (same ▸ stored)
            · exact .inl later
          · exact .inr done
        · intro item member child dependency
          rcases valid.closed item member child dependency with queued | done
          · rcases List.mem_cons.mp queued with same | later
            · exact .inr (same ▸ stored)
            · exact .inl later
          · exact .inr done
        · intro item member
          apply valid.sound
          rcases member with queued | done
          · exact .inl (List.mem_cons_of_mem _ queued)
          · exact .inr done
      · have absent : id ∉ order := by
          intro member; exact visited ((valid.membership id).mpr member)
        have reached := valid.sound id (.inl (by simp))
        simp only [step, visited, Bool.false_eq_true, ↓reduceIte]
        constructor
        · intro item
          simp only [Std.HashSet.contains_insert, Bool.or_eq_true, beq_iff_eq,
            List.mem_append, List.mem_singleton]
          exact (or_congr eq_comm (valid.membership item)).trans or_comm
        · apply List.nodup_append.mpr
          refine ⟨valid.unique, by simp, ?_⟩
          intro item member other singleton same
          have last : other = id := by simpa using singleton
          exact absent (last ▸ same ▸ member)
        · intro item member
          exact move_membership id item rest order (edges id) (valid.rootsCovered item member)
        · intro item member child dependency
          rcases List.mem_append.mp member with earlier | latest
          · exact move_membership id child rest order (edges id) (valid.closed item earlier child dependency)
          · have same : item = id := by simpa using latest
            subst item
            exact .inl (List.mem_append_left _ dependency)
        · intro item member
          rcases member with queued | done
          · rcases List.mem_append.mp queued with dependency | sibling
            · exact .dependency reached dependency
            · exact valid.sound item (.inl (by simp [sibling]))
          · rcases List.mem_append.mp done with earlier | latest
            · exact valid.sound item (.inr earlier)
            · have same : item = id := by simpa using latest
              exact same ▸ reached

theorem walk_invariant (valid : Invariant edges roots s) :
    Invariant edges roots (walk edges fuel s) := by
  induction fuel generalizing s with
  | zero => exact valid
  | succ fuel ih =>
    cases pending : s.pending with
    | nil => simpa [walk, pending] using valid
    | cons id rest => simpa [walk, pending] using ih (step_invariant valid)

def initial (roots : List Nat) : State := ⟨roots, {}, []⟩

theorem initial_invariant (edges : Edges) (roots : List Nat) :
    Invariant edges roots (initial roots) := by
  refine ⟨by simp [initial], by simp [initial], by simp [initial], by simp [initial], ?_⟩
  intro id member
  exact .root (by simpa [initial] using member)

def discover (vertices : List Nat) (edges : Edges) (roots : List Nat) : State :=
  walk edges (measure vertices edges (initial roots)) (initial roots)

theorem discover_drained (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) :
    (discover vertices edges roots).pending = [] :=
  walk_drains closed rootsWithin (Nat.le_refl _)

theorem discover_nodup : (discover vertices edges roots).order.Nodup :=
  (walk_invariant (initial_invariant edges roots)).unique

theorem discover_exact (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) (id : Nat) :
    id ∈ (discover vertices edges roots).order ↔ Reached edges roots id := by
  have valid := walk_invariant (fuel := measure vertices edges (initial roots))
    (initial_invariant edges roots)
  have drained := discover_drained closed rootsWithin
  constructor
  · intro member; exact valid.sound id (.inr member)
  · intro reached
    induction reached with
    | root member =>
      have covered := valid.rootsCovered _ member
      change _ ∈ (discover vertices edges roots).pending ∨ _ ∈ (discover vertices edges roots).order at covered
      simpa [drained] using covered
    | dependency parent member ih =>
      have covered := valid.closed _ ih _ member
      change _ ∈ (discover vertices edges roots).pending ∨ _ ∈ (discover vertices edges roots).order at covered
      simpa [drained] using covered

-- The second pass uses the ACTUAL hash-key enumeration, not a sorted ID order.
def finalOps (order : List Nat) (recorded current : Nat → Binding) : List Op :=
  order.map (fun id => .token (toString id) (recorded id) (current id))

theorem final_check_exact (order : List Nat) (recorded current : Nat → Binding) (world : World) :
    firstIssue (finalOps order recorded current) world = none ↔
      ∀ id ∈ order, recorded id = current id := by
  induction order with
  | nil => simp [finalOps, firstIssue]
  | cons id rest ih =>
    simp only [finalOps, List.map_cons, firstIssue]
    by_cases same : recorded id = current id <;> simp [same, finalOps] at *
    · exact ih

/-- A hash-key enumeration must contain exactly the seen identities. Its order
is intentionally a parameter, since native hash enumeration is not canonical. -/
theorem final_covers_discovery (order : List Nat)
    (enumeration : order.Perm (discover vertices edges roots).order)
    (recorded current : Nat → Binding) (world : World)
    (accepted : firstIssue (finalOps order recorded current) world = none) :
    ∀ id ∈ (discover vertices edges roots).order, recorded id = current id := by
  have all := (final_check_exact order recorded current world).mp accepted
  intro id member
  exact all id ((enumeration.mem_iff).mpr member)

theorem final_rejects_changed_record (order : List Nat)
    (recorded current : Nat → Binding) (world : World) (id : Nat)
    (member : id ∈ order) (changed : recorded id ≠ current id) :
    firstIssue (finalOps order recorded current) world ≠ none := by
  intro accepted
  exact changed ((final_check_exact order recorded current world).mp accepted id member)

theorem final_covers_reachable (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices) (order : List Nat)
    (enumeration : order.Perm (discover vertices edges roots).order)
    (recorded current : Nat → Binding) (world : World)
    (accepted : firstIssue (finalOps order recorded current) world = none)
    (id : Nat) (reached : Reached edges roots id) : recorded id = current id :=
  final_covers_discovery order enumeration recorded current world accepted id
    ((discover_exact closed rootsWithin id).mpr reached)

def visitOps (ids : List Nat) (recorded current : Nat → Binding)
    (sourceOps : Nat → List Op) : List Op :=
  ids.flatMap (fun id => .token (toString id) (recorded id) (current id) :: sourceOps id)

private theorem source_ops_exact (requests : List Request) :
    sources (requests.map Op.source) = requests := by
  induction requests with
  | nil => rfl
  | cons request rest ih => simp [sources, ih]

theorem graph_source_projection (ids : List Nat) (recorded current : Nat → Binding)
    (requests : Nat → List Request) :
    sources (visitOps ids recorded current (fun id => (requests id).map Op.source)) =
      ids.flatMap requests := by
  induction ids with
  | nil => rfl
  | cons id rest ih =>
    simpa [visitOps, sources, sources_append, source_ops_exact] using
      congrArg (fun tail => requests id ++ tail) ih

theorem accepted_reachable_source (closed : Closed vertices edges)
    (rootsWithin : ∀ id ∈ roots, id ∈ vertices)
    (recorded current : Nat → Binding) (requests : Nat → List Request)
    (world : World) (cache : Bytes)
    (accepted : (run (visitOps (discover vertices edges roots).order recorded current
      (fun id => (requests id).map Op.source)) world cache).issue = none)
    (id : Nat) (reached : Reached edges roots id) (request : Request)
    (member : request ∈ requests id) :
    request ∈ (run (visitOps (discover vertices edges roots).order recorded current
      (fun id => (requests id).map Op.source)) world cache).observed := by
  rw [successful_coverage _ _ _ accepted, graph_source_projection]
  exact List.mem_flatMap.mpr ⟨id, (discover_exact closed rootsWithin id).mpr reached, member⟩

-- Direct reuse of the prior exact diagnostic theorem, now on a graph trace.
theorem graph_ordered_diagnostic (ids finalOrder : List Nat)
    (recorded during after : Nat → Binding) (sourceOps : Nat → List Op)
    (world : World) (cache : Bytes) (sound : Sound cache world) :
    (run (visitOps ids recorded during sourceOps ++ finalOps finalOrder recorded after)
      world cache).issue =
    firstIssue (visitOps ids recorded during sourceOps ++ finalOps finalOrder recorded after) world :=
  ordered_diagnostic_exact _ _ _ sound

private def diamondCycle : Edges
  | 0 => [1, 2]
  | 1 => [3]
  | 2 => [3]
  | 3 => [1]
  | _ => []

-- Shared node 3, cycle 1→3→1, duplicate root 0; disconnected 4 stays unvisited.
theorem diamond_cycle_discovery :
    (discover [0, 1, 2, 3, 4] diamondCycle [0, 0]).pending = [] ∧
    (discover [0, 1, 2, 3, 4] diamondCycle [0, 0]).order = [0, 1, 3, 2] := by
  simp [discover, measure, unseenWeight, initial, diamondCycle, walk, step,
    Std.HashSet.contains_insert]

/-- Projection of object.ss clear-object-cache!: cache clearing itself does not
advance the mutation revision. This is NOT a callback purity declaration. -/
structure MetadataState where
  revision : Nat
  precedence : Option (List Nat)

def clearMetadata (state : MetadataState) : MetadataState :=
  { state with precedence := none }

theorem same_revision_does_not_imply_prepared (revision : Nat) (order : List Nat) :
    (clearMetadata ⟨revision, some order⟩).revision = revision ∧
    (clearMetadata ⟨revision, some order⟩).precedence = none := ⟨rfl, rfl⟩

end YuanxuProof.Admission.IdentityDFS
