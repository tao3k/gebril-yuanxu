-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.IssuedLoading
namespace YuanxuProof.Admission.SourceLoader

def quintSourceDigest : String := "sha256:b77d2376db705d5902be2fbf0c3cf566d9a448b790ef42831ab902c5877beba6"

-- These are compiled call edges, not the current value of a mutable SDK binding.
inductive Edge where
  | saved | direct | reload | retry
  deriving DecidableEq

def checked (_ : Edge) : Bool := true
def returnsCached (edge : Edge) (changed : Bool) : Bool :=
  !(checked edge && changed)

theorem changed_cache_refused (edge : Edge) : returnsCached edge true = false := by
  simp [returnsCached, checked]

theorem stable_cache_allowed (edge : Edge) : returnsCached edge false = true := by
  simp [returnsCached, checked]

-- Rebinding elsewhere cannot change the entry of a source-compiled procedure.
theorem saved_edge_independent_of_rebinding (changed : Bool) :
    returnsCached .saved changed = returnsCached .direct changed := rfl

def publish (returned a b : Bool) : Bool := returned && a && b
theorem both_requirements (returned a b : Bool) (h : publish returned a b = true) :
    a = true ∧ b = true := by
  simp only [publish, Bool.and_eq_true] at h
  exact ⟨h.1.2, h.2⟩

-- An old compiled procedure is a different edge; the new body cannot repair it.
def legacyReturnsCached (_changed : Bool) : Bool := true
theorem old_edge_counterexample :
    legacyReturnsCached true = true ∧ returnsCached .saved true = false := by
  decide

end YuanxuProof.Admission.SourceLoader
