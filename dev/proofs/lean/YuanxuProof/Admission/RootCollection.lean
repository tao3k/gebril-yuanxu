-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReadRetention

namespace YuanxuProof.Admission.RootCollection

def quintSourceDigest : String :=
  "sha256:5e40ce32b6ec4a13f91b7ec3c0a537e652bb48557f689cb9d507b090570b49ee"

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

end YuanxuProof.Admission.RootCollection
