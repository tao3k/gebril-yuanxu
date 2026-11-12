-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Selection.Requirements
import YuanxuProof.Admission.BoundaryComposition

/-! The selected resolver order is an input, not a second graph resolver.
`Scope` abstracts a POO receiver. Runtime write fencing and complete read/source
capture remain Scheme correspondence obligations. Feature Contracts check the
same final, Core-normalized receiver; they do not replace it with their outputs. -/
namespace YuanxuProof.ModuleSystem.Selection.FeatureScopes

def compose {Scope Feature : Type} (refine : Scope → Feature → Scope)
    (base : Scope) (selected : List Feature) : Scope :=
  selected.foldl refine base

def accepted {Scope Contract : Type} (holds : Contract → Scope → Prop)
    (core : Contract) (selected : List Contract) (final : Scope) : Prop :=
  holds core final ∧ ∀ contract ∈ selected, holds contract final

theorem empty_selection_is_base {Scope Feature : Type}
    (refine : Scope → Feature → Scope) (base : Scope) :
    compose refine base [] = base := rfl

theorem dependency_order_preserved {Scope Feature : Type}
    (refine : Scope → Feature → Scope) (base : Scope) (first : Feature)
    (rest : List Feature) :
    compose refine base (first :: rest) = compose refine (refine base first) rest := rfl

/-- Withdrawal starts from base, not from the previously extended instance. -/
theorem withdrawal_does_not_retain_parent {Scope Feature : Type}
    (refine : Scope → Feature → Scope) (base : Scope) (old : List Feature)
    (remaining : List Feature) :
    (compose refine base old, compose refine base remaining).2 =
      compose refine base remaining := rfl

theorem final_core_obligation {Scope Contract : Type}
    (holds : Contract → Scope → Prop) (core : Contract)
    (selected : List Contract) (final : Scope)
    (ok : accepted holds core selected final) : holds core final := ok.1

theorem every_selected_obligation {Scope Contract : Type}
    (holds : Contract → Scope → Prop) (core : Contract)
    (selected : List Contract) (final : Scope)
    (ok : accepted holds core selected final) (contract : Contract)
    (member : contract ∈ selected) : holds contract final := ok.2 contract member

theorem conflicting_contributions_refuse {Scope Contract : Type}
    (holds : Contract → Scope → Prop) (core a b : Contract)
    (selected : List Contract) (final : Scope)
    (first : a ∈ selected) (second : b ∈ selected)
    (conflict : ∀ candidate, ¬ (holds a candidate ∧ holds b candidate)) :
    ¬ accepted holds core selected final := by
  intro ok
  exact conflict final ⟨ok.2 a first, ok.2 b second⟩

/-- `closure` denotes Gerbil's import closure for each selected Feature facade.
Build input admission and compiler identity deduplication are separate. -/
def compilerTargets {Feature Target : Type} (core : List Target)
    (closure : Feature → List Target) (selected : List Feature) : List Target :=
  core ++ selected.flatMap closure

theorem compiler_target_support {Feature Target : Type} (core : List Target)
    (closure : Feature → List Target) (selected : List Feature) (target : Target) :
    target ∈ compilerTargets core closure selected ↔
      target ∈ core ∨ ∃ feature ∈ selected, target ∈ closure feature := by
  simp [compilerTargets, List.mem_flatMap]

theorem withdrawal_removes_exclusive_target {Feature Target : Type}
    (core : List Target) (closure : Feature → List Target) (retained : List Feature)
    (target : Target) (notCore : target ∉ core)
    (notRetained : ∀ feature ∈ retained, target ∉ closure feature) :
    target ∉ compilerTargets core closure retained := by
  intro present
  rcases (compiler_target_support core closure retained target).mp present with common | ⟨feature, member, support⟩
  · exact notCore common
  · exact notRetained feature member support

end YuanxuProof.ModuleSystem.Selection.FeatureScopes
