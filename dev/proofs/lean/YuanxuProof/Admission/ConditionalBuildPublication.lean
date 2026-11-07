-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreApprovedRecovery
import YuanxuProof.Admission.SerialUse

namespace YuanxuProof.Admission.ConditionalBuildPublication

def quintSourceDigest : String :=
  "sha256:794c379c0391656d2cc81b81abb6c98f723bd3fd9746f23dc26ca243c28336db"

-- Reuse the existing recovery gates and external-owner version relation.
def eligible (restored approval source files a b : Bool) (expected live : Nat) : Bool :=
  CoreApprovedRecovery.finish restored approval source files a b &&
    SerialUse.conditionalCommit true expected live

theorem commit_keeps_requirements_and_revision
    (restored approval source files a b : Bool) (expected live : Nat)
    (h : eligible restored approval source files a b expected live = true) :
    approval = true ∧ source = true ∧ files = true ∧ a = true ∧ b = true ∧ expected = live := by
  have expanded : restored = true ∧ approval = true ∧ source = true ∧
      files = true ∧ a = true ∧ b = true ∧ expected = live := by
    simpa [eligible, CoreApprovedRecovery.finish, SerialUse.conditionalCommit,
      Bool.and_eq_true, and_assoc] using h
  exact expanded.2

theorem aba_refused (restored approval source files a b : Bool) (version : Nat) :
    eligible restored approval source files a b version (version + 2) = false := by
  simp [eligible, SerialUse.conditionalCommit]

-- The owner installs the captured payload; it does not re-project mutable inputs.
def install (payload : Nat) (allowed : Bool) (previous : Nat) : Nat :=
  if allowed then payload else previous

theorem uses_exact_admitted_plan (payload previous : Nat) :
    install payload true previous = payload := rfl

theorem refusal_preserves_head (payload previous : Nat) :
    install payload false previous = previous := rfl

theorem child_install_preserves_parent (parent payload : Nat) :
    (parent, install payload true parent).1 = parent := rfl

-- Explicit countermodel: an uncoordinated external writer does not advance
-- the owner's token. This protocol alone cannot detect that change.
theorem external_change_not_covered (version : Nat) :
    eligible true true true true true true version version = true := by
  simp [eligible, CoreApprovedRecovery.finish, SerialUse.conditionalCommit]

end YuanxuProof.Admission.ConditionalBuildPublication
