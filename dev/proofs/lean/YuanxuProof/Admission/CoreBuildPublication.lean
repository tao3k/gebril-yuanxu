-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SourceLoader
namespace YuanxuProof.Admission.CoreBuildPublication

def quintSourceDigest : String := "sha256:1c6485d5fe668cee79e5ccf7f2ea36ec4d2e208c1ba06d6300114b096f163aea"

def current (expected artifact record : String) : Bool :=
  expected == artifact && expected == record
def publish (before after a b : Bool) : Bool := before && after && a && b

theorem joint_replacement_refused (expected replaced : String) (h : expected ≠ replaced) :
    current expected replaced replaced = false := by simp [current, h]
theorem publication_requires_final_check (before a b : Bool) :
    publish before false a b = false := by simp [publish]
theorem both_requirements (before after a b : Bool)
    (h : publish before after a b = true) : a = true ∧ b = true := by
  simp only [publish, Bool.and_eq_true] at h
  exact ⟨h.1.2, h.2⟩
-- Native load/cache behavior is deliberately not an input to Core admission.
def nativeIndependent (_nativeReturned : Bool) (before after a b : Bool) : Bool :=
  publish before after a b
theorem native_cache_grants_no_authority (before after a b : Bool) :
    nativeIndependent true before after a b = nativeIndependent false before after a b := rfl
inductive Entry where
  | saved | direct | forExport
def enter (_entry : Entry) (e f r : String) : Bool := current e f r
theorem saved_entry_uses_same_check (e f r : String) :
    enter .saved e f r = enter .direct e f r := rfl
-- Fresh compiler output has no existing file for native make to adopt.
-- This is output ownership, not an asserted user purity/force flag.
def completedOutput (fresh : Bool) (native cache : String) : String :=
  if fresh then native else cache
theorem first_build_cannot_adopt_cache (native cache : String) :
    completedOutput true native cache = native := rfl
theorem unchecked_adoption_counterexample :
    completedOutput false "compiled" "poisoned" ≠ "compiled" := by decide
end YuanxuProof.Admission.CoreBuildPublication
