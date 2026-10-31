-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreStoreRecovery
namespace YuanxuProof.Admission.CoreApprovedRecovery

def quintSourceDigest : String := "sha256:afe6c07216d82ded02b212a24d87878a9a4943e8b915e3f846d257d8bbd6079e"

-- Obtaining the Source from governed package policy is a bootstrap premise.
-- An initial approved Source is distinct from its later currentness result.
def finish (restored approval source files a b : Bool) : Bool :=
  restored && approval && source && files && a && b

def restore (installed covered source files : Bool) : Bool :=
  installed && covered && source && files

theorem noop_cannot_restore (covered source files : Bool) :
    restore false covered source files = false := by simp [restore]

abbrev Observation := String × Option String
def covers (selected packet : List Observation) : Bool :=
  selected.all (fun row => packet.contains row)

theorem coverage_requires_each_selected (selected packet : List Observation)
    (h : covers selected packet = true) : ∀ row ∈ selected, row ∈ packet := by
  simpa [covers, List.all_eq_true] using h

theorem omission_refused :
    covers [("init.ss", some "selected")] [] = false := by decide

theorem replacement_refused :
    covers [("init.ss", some "selected")] [("init.ss", some "other")] = false := by decide

theorem changed_approval_refused (restored source files a b : Bool) :
    finish restored false source files a b = false := by simp [finish]

theorem changed_source_refused (restored approval files a b : Bool) :
    finish restored approval false files a b = false := by simp [finish]

theorem joint_replacement_refused (restored approval source a b : Bool) :
    finish restored approval source false a b = false := by simp [finish]

theorem accepted_preserves_boundaries (restored approval source files a b : Bool)
    (h : finish restored approval source files a b = true) :
    approval = true ∧ source = true ∧ files = true ∧ a = true ∧ b = true := by
  simp only [finish, Bool.and_eq_true] at h
  exact ⟨h.1.1.1.1.2, h.1.1.1.2, h.1.1.2, h.1.2, h.2⟩

theorem restart_has_accepting_path : finish true true true true true true = true := by decide

theorem dropping_approval_is_unsound :
    (true && true && true && true && true) = true ∧
    finish true false true true true true = false := by decide

-- Registry receiver isolation remains CoreBuildHandoff.parent_receiver_isolation.
end YuanxuProof.Admission.CoreApprovedRecovery
