-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SerialUse
namespace YuanxuProof.Admission.IssuedRootForwarding

def quintSourceDigest : String :=
  "sha256:cff23745d63d20dc0817918828cf8bb965641b45fd35e105e63cc7834ffeb80f"

-- Tokens denote original registry identities, not reconstructed record payloads.
def forward (roots : List Nat) : List Nat := roots.eraseDups

theorem exact_membership (roots : List Nat) (token : Nat) :
    token ∈ forward roots ↔ token ∈ roots := by simp [forward]

def Authentic (issued : Nat → Prop) (roots : List Nat) : Prop :=
  ∀ token ∈ roots, issued token

theorem preserves_issuance (issued : Nat → Prop) (roots : List Nat)
    (h : Authentic issued roots) : Authentic issued (forward roots) := by
  intro token ht
  exact h token ((exact_membership roots token).mp ht)

theorem cannot_hide_unissued (issued : Nat → Prop) (roots : List Nat) (token : Nat)
    (member : token ∈ roots) (foreign : ¬ issued token) :
    ¬ Authentic issued (forward roots) := by
  intro accepted
  exact foreign (accepted token ((exact_membership roots token).mpr member))

inductive Reach (roots : List Nat) (dependencies : Nat → List Nat) : Nat → Prop where
  | root {token} : token ∈ roots → Reach roots dependencies token
  | child {parent token} : Reach roots dependencies parent →
      token ∈ dependencies parent → Reach roots dependencies token

theorem forward_keeps_dependency_closure (roots : List Nat) (dependencies : Nat → List Nat)
    (token : Nat) : Reach (forward roots) dependencies token ↔ Reach roots dependencies token := by
  constructor
  · intro h
    induction h with
    | root ht => exact .root ((exact_membership roots _).mp ht)
    | child _ ht ih => exact .child ih ht
  · intro h
    induction h with
    | root ht => exact .root ((exact_membership roots _).mpr ht)
    | child _ ht ih => exact .child ih ht

-- Currentness is checked independently of token authenticity; successful
-- forwarding is never a cached approval for later source/receiver changes.
def admissible (issued current a b : Bool) : Bool := issued && current && a && b
theorem changed_source_refused (issued a b : Bool) :
    admissible issued false a b = false := by simp [admissible]
theorem both_requirements_retained (issued current a b : Bool)
    (h : admissible issued current a b = true) : a = true ∧ b = true := by
  simp only [admissible, Bool.and_eq_true] at h
  exact ⟨h.1.2, h.2⟩
end YuanxuProof.Admission.IssuedRootForwarding
