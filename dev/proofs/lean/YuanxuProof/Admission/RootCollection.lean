-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReadRetention

namespace YuanxuProof.Admission.RootCollection

def quintSourceDigest : String :=
  "sha256:ef3d878991dbcdfa9984e52c1123d00435aee8c6cc0db033676d4a7d7d798c6a"

-- Token Nat is original record identity. Observers see the uncompressed input.
structure Frame (World : Type) where
  roots : List Nat
  world : World

def step (observe : World → Nat → World) (frame : Frame World) (token : Nat) : Frame World :=
  ⟨if token ∈ frame.roots then frame.roots else frame.roots ++ [token],
    observe frame.world token⟩

theorem callbacks_unchanged (observe : World → Nat → World)
    (input : List Nat) (frame : Frame World) :
    (input.foldl (step observe) frame).world = input.foldl observe frame.world := by
  induction input generalizing frame with
  | nil => rfl
  | cons token rest ih => simpa [step] using ih (step observe frame token)

theorem append_identity (input : List Nat) (token : Nat) :
    (input ++ [token]).eraseDups =
      if token ∈ input then input.eraseDups else input.eraseDups ++ [token] := by
  rw [List.eraseDups_append]
  by_cases h : token ∈ input <;> simp [List.removeAll, h, List.eraseDups_cons]

theorem roots_are_original_first_occurrences (observe : World → Nat → World)
    (input prior : List Nat) (world : World) :
    (input.foldl (step observe) ⟨prior.eraseDups, world⟩).roots =
      (prior ++ input).eraseDups := by
  induction input generalizing prior world with
  | nil => simp
  | cons token rest ih =>
    simp only [List.foldl_cons, step]
    have h := ih (prior ++ [token]) (observe world token)
    simpa [append_identity, List.append_assoc] using h

/-- Native child capture already delivered inherited observers at each actual
read. Merging that capture records roots ONLY; it is not another delivery.
The Boolean is the existing parent collection policy, not a purity flag. -/
def mergeCaptured (unique : Bool) (parent : Frame World) (captured : List Nat) : Frame World :=
  ⟨if unique then
      (captured.foldl (step (fun world _ => world)) parent).roots
    else parent.roots ++ captured, parent.world⟩

theorem merge_does_not_redeliver (unique : Bool) (parent : Frame World)
    (captured : List Nat) :
    (mergeCaptured unique parent captured).world = parent.world := rfl

theorem merge_occurrences (parent : Frame World) (captured : List Nat) :
    (mergeCaptured false parent captured).roots = parent.roots ++ captured := rfl

theorem merge_original_identities (prior captured : List Nat) (world : World) :
    (mergeCaptured true ⟨prior.eraseDups, world⟩ captured).roots =
      (prior ++ captured).eraseDups :=
  roots_are_original_first_occurrences (fun world _ => world) captured prior world

theorem capture_then_merge_keeps_callbacks (unique : Bool) (prior input : List Nat)
    (observe : World → Nat → World) (world : World) :
    (mergeCaptured unique ⟨prior, input.foldl observe world⟩ input.eraseDups).world =
      input.foldl observe world := rfl

theorem skip_nonfailure (input : List Nat) (bad : Nat → Bool) (token : Nat)
    (good : bad token = false) :
    (input.filter (fun n => !(n == token))).find? bad = input.find? bad := by
  induction input with
  | nil => rfl
  | cons head rest ih =>
    by_cases same : head = token
    · subst head; simp [good, ih]
    · simp [same, ih, List.find?_cons]

theorem first_diagnostic_unchanged (input : List Nat) (bad : Nat → Bool) :
    input.eraseDups.find? bad = input.find? bad := by
  cases input with
  | nil => rfl
  | cons token rest =>
    rw [List.eraseDups_cons]
    simp only [List.find?_cons]
    cases good : bad token with
    | true => rfl
    | false =>
      rw [first_diagnostic_unchanged]
      exact skip_nonfailure rest bad token good
termination_by input.length
decreasing_by simp_wf; exact Nat.lt_succ_of_le (List.length_filter_le _ _)

theorem dependency_binding_retained (dependencies : Nat → List Nat) (input : List Nat)
    (token : Nat) (present : token ∈ input) :
    (token, dependencies token) ∈ input.eraseDups.map (fun n => (n, dependencies n)) := by
  exact List.mem_map.mpr ⟨token, by simpa using present, rfl⟩

theorem demanded_closure_unchanged (input : List Nat) (dependencies : Nat → List Nat)
    (token : Nat) :
    IssuedRootForwarding.Reach input.eraseDups dependencies token ↔
      IssuedRootForwarding.Reach input dependencies token :=
  IssuedRootForwarding.forward_keeps_dependency_closure input dependencies token

-- Roots are native issuance identities. Only a dependency-free leaf can be
-- removed directly. The escape analysis which marks such a leaf is separate.
theorem private_leaf_removal_keeps_external_reach
    (roots : List Nat) (dependencies : Nat → List Nat) (keep : Nat → Bool)
    (leaves : ∀ token ∈ roots, keep token = false → dependencies token = [])
    (token : Nat) (external : keep token = true) :
    IssuedRootForwarding.Reach (roots.filter keep) dependencies token ↔
      IssuedRootForwarding.Reach roots dependencies token := by
  constructor
  · intro reached
    clear external
    induction reached with
    | root member => exact .root (List.mem_filter.mp member).1
    | child _ edge ih => exact .child ih edge
  · intro reached
    have preserve {n : Nat} (original : IssuedRootForwarding.Reach roots dependencies n) :
        keep n = true ∨ dependencies n ≠ [] →
          IssuedRootForwarding.Reach (roots.filter keep) dependencies n := by
      induction original with
      | @root root member =>
        intro required
        cases kept : keep root with
        | true => exact .root (List.mem_filter.mpr ⟨member, kept⟩)
        | false => simp [kept, leaves root member kept] at required
      | @child parent child _ edge ih =>
        intro _
        exact .child (ih (.inr (by intro empty; simp [empty] at edge))) edge
    exact preserve reached (.inl external)

-- Order is already supplied by the issued traversal. The local complete
-- check owns failures during construction. A later projection only erases
-- leaves that cannot fail in that later snapshot.
theorem private_leaf_removal_keeps_first_refusal
    (traversal : List Nat) (keep bad : Nat → Bool)
    (valid : ∀ token ∈ traversal, keep token = false → bad token = false) :
    (traversal.filter keep).find? bad = traversal.find? bad := by
  induction traversal with
  | nil => rfl
  | cons token rest ih =>
    have tail := ih (fun n member => valid n (by simp [member]))
    cases kept : keep token with
    | false =>
      have good := valid token (by simp) kept
      simp [kept, good, tail]
    | true => simp [List.find?_cons, kept, tail]

theorem leaked_leaf_can_change_refusal :
    ([1, 2].filter (· != 1)).find? (· == 1) ≠ [1, 2].find? (· == 1) := by decide

-- The local complete authentication still owns every issued read. Its
-- external projection can omit a private intermediate record with outgoing
-- dependencies by retaining the actual external records reached through it.
-- No retained native record may depend on an omitted one: a signed edge
-- cannot be edited merely to make the projection smaller.
theorem private_subgraph_projection_keeps_external_reach
    (roots traversal : List Nat) (deps : Nat → List Nat) (privateRead : Nat → Bool)
    (complete : ∀ token, token ∈ traversal ↔ IssuedRootForwarding.Reach roots deps token)
    (closed : ∀ parent child, IssuedRootForwarding.Reach roots deps parent →
      privateRead parent = false → child ∈ deps parent → privateRead child = false)
    (token : Nat) :
    IssuedRootForwarding.Reach (traversal.filter (fun read => !privateRead read)) deps token ↔
      IssuedRootForwarding.Reach roots deps token ∧ privateRead token = false := by
  constructor
  · intro reached
    induction reached with
    | root member =>
      have retained := List.mem_filter.mp member
      exact ⟨(complete _).mp retained.1, by simpa using retained.2⟩
    | child _ edge ih =>
      exact ⟨.child ih.1 edge, closed _ _ ih.1 ih.2 edge⟩
  · intro retained
    exact .root (List.mem_filter.mpr ⟨(complete _).mpr retained.1, by simpa using retained.2⟩)

theorem retained_read_cannot_hide_its_private_child
    (roots : List Nat) (deps : Nat → List Nat) (parent child : Nat)
    (retained : IssuedRootForwarding.Reach roots deps parent)
    (edge : child ∈ deps parent) :
    IssuedRootForwarding.Reach roots deps child := .child retained edge

-- A session already owns ordered publication rows. Recording their issued
-- roots into one native unique collection retains the first identity across
-- row boundaries, without allocating the repeated concatenated spine.
def recordSessionRows (rows : List (List Nat)) : List Nat :=
  (rows.foldl (mergeCaptured true) ⟨[], ()⟩).roots

theorem record_session_rows_first_occurrences (rows : List (List Nat)) :
    recordSessionRows rows = rows.flatten.eraseDups := by
  unfold recordSessionRows
  have collect (remaining : List (List Nat)) (prior : List Nat) :
      (remaining.foldl (mergeCaptured true) ⟨prior.eraseDups, ()⟩).roots =
        (prior ++ remaining.flatten).eraseDups := by
    induction remaining generalizing prior with
    | nil => simp
    | cons next rest ih =>
      simp only [List.foldl_cons, List.flatten_cons]
      have stepEq : mergeCaptured true ⟨prior.eraseDups, ()⟩ next =
          (⟨(prior ++ next).eraseDups, ()⟩ : Frame Unit) := by
        cases h : mergeCaptured true ⟨prior.eraseDups, ()⟩ next with
        | mk roots world =>
          have rootsEq := merge_original_identities prior next ()
          rw [h] at rootsEq
          cases world
          exact congrArg (fun captured => (⟨captured, ()⟩ : Frame Unit)) rootsEq
      rw [stepEq, ih, List.append_assoc]
  simpa using collect rows []

theorem record_session_rows_preserves_refusal (rows : List (List Nat)) (bad : Nat → Bool) :
    (recordSessionRows rows).find? bad = rows.flatten.find? bad := by
  rw [record_session_rows_first_occurrences, first_diagnostic_unchanged]

theorem record_session_rows_preserves_reach (rows : List (List Nat)) (deps : Nat → List Nat)
    (token : Nat) :
    IssuedRootForwarding.Reach (recordSessionRows rows) deps token ↔
      IssuedRootForwarding.Reach rows.flatten deps token := by
  rw [record_session_rows_first_occurrences]
  exact demanded_closure_unchanged rows.flatten deps token

end YuanxuProof.Admission.RootCollection
