-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreBuildHandoff
namespace YuanxuProof.Admission.CoreStoreRecovery

def quintSourceDigest : String := "sha256:105352d90dcb17f0ed6465dca8af52a6552eaf260782cb8cdaae7c785f97ba92"

-- The selected path comes from release policy, independently of the candidate.
-- registered/nar are results of the real Nix database/content checks. Lean does
-- not prove Nix or authenticate a mutable caller-supplied selection policy.
def rootAdmitted (selected candidate : String) (registered nar : Bool) : Bool :=
  (selected == candidate) && registered && nar

def recover (selected candidate : String) (registered nar regular source artifact record : Bool) : Bool :=
  rootAdmitted selected candidate registered nar && regular && source && artifact && record

theorem valid_other_store_refused (selected candidate : String)
    (h : selected ≠ candidate) (regular source artifact record : Bool) :
    recover selected candidate true true regular source artifact record = false := by
  simp [recover, rootAdmitted, h]

theorem stable_restart (selected : String) :
    recover selected selected true true true true true true = true := by
  simp [recover, rootAdmitted]

theorem joint_replacement_refused (selected : String) :
    recover selected selected true true true true false false = false := by
  simp [recover]

theorem changed_source_refused (selected candidate : String) (registered nar regular artifact record : Bool) :
    recover selected candidate registered nar regular false artifact record = false := by
  simp [recover]

theorem nonregular_issuance_refused (selected candidate : String)
    (registered nar source artifact record : Bool) :
    recover selected candidate registered nar false source artifact record = false := by
  simp [recover]

theorem recovery_requires_registered_contents (selected candidate : String)
    (registered nar regular source artifact record : Bool)
    (h : recover selected candidate registered nar regular source artifact record = true) :
    registered = true ∧ nar = true := by
  simp only [recover, rootAdmitted, Bool.and_eq_true] at h
  exact ⟨h.1.1.1.1.1.2, h.1.1.1.1.2⟩

theorem integrity_without_selection_counterexample :
    (true && true) = true ∧ rootAdmitted "approved" "other-valid" true true = false := by
  decide

-- Final publication and receiver isolation reuse the existing protocol laws:
-- CoreBuildHandoff.final_and_both_requirements / parent_receiver_isolation.
end YuanxuProof.Admission.CoreStoreRecovery
