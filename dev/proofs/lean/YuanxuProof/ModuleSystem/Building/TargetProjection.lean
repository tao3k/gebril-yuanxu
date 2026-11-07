-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

namespace YuanxuProof.ModuleSystem.Building.TargetProjection

/-- Native rows retain the owner, source, output identity, and options. -/
structure Target where
  owner : String
  source : String
  output : String
  options : List String
  deriving DecidableEq

structure PreparedTarget where
  target : Target
  compilerInput : Nat

def targets (selected : List (List Target)) (retained : List Target) : List Target :=
  selected.flatten ++ retained

def prepare (rows : List Target) (input : Target → Nat) : List PreparedTarget :=
  rows.map fun row => ⟨row, input row⟩

/-- Compiler preparation cannot change any row, its position, or its options. -/
theorem prepared_targets_eq (selected : List (List Target)) (retained : List Target)
    (input : Target → Nat) :
    (prepare (targets selected retained) input).map PreparedTarget.target =
      targets selected retained := by
  simp [prepare, List.map_map, Function.comp_def]

theorem same_name_is_not_target_equality (left right : Target)
    (optionsChanged : left.options ≠ right.options) : left ≠ right := by
  intro equal
  exact optionsChanged (congrArg Target.options equal)

def admitTarget (seen : List Target) (candidate : Target) :
    Except String (List Target) :=
  match seen.find? (fun row => row.output == candidate.output || row.source == candidate.source) with
  | none => .ok (seen ++ [candidate])
  | some prior => if prior = candidate then .ok seen else .error candidate.output

theorem duplicate_keeps_first (row : Target) :
    admitTarget [row] row = .ok [row] := by
  simp [admitTarget]

theorem changed_options_reject (left right : Target) (sameOutput : left.output = right.output)
    (changed : left.options ≠ right.options) :
    admitTarget [left] right = .error right.output := by
  simp [admitTarget, sameOutput, same_name_is_not_target_equality left right changed]

theorem repeated_source_cannot_change_output (left right : Target) (sameSource : left.source = right.source)
    (changed : left.output ≠ right.output) :
    admitTarget [left] right = .error right.output := by
  have different : left ≠ right := fun equal => changed (congrArg Target.output equal)
  simp [admitTarget, sameSource, different]

/-- A projection cannot be complete from a common observation when expansion
adds an output in only one of the two sources. -/
theorem incomplete_observation_cannot_determine_targets
    {Observation Source : Type}
    (observe : Source → Observation) (nativeTargets : Source → List Target)
    (left right : Source) (indistinguishable : observe left = observe right)
    (different : nativeTargets left ≠ nativeTargets right) :
    ¬ ∃ project : Observation → List Target, ∀ source, project (observe source) = nativeTargets source := by
  rintro ⟨project, correct⟩
  apply different
  calc
    nativeTargets left = project (observe left) := (correct left).symm
    _ = project (observe right) := congrArg project indistinguishable
    _ = nativeTargets right := correct right

/-- For a closed owner, imported targets are checked against the native rows
already owned by the selection. They do not extend the Make spec. -/
def checkTargetCoverage (owned demanded : List Target) : Except String (List Target) :=
  if demanded.all (fun row => decide (row ∈ owned)) then .ok owned
  else .error "unowned compiler target"

theorem covered_demands_preserve_order (owned demanded : List Target)
    (covered : ∀ row ∈ demanded, row ∈ owned) :
    checkTargetCoverage owned demanded = .ok owned := by
  simpa [checkTargetCoverage, List.all_eq_true] using covered

theorem unowned_import_refuses (owned demanded : List Target) (row : Target)
    (demandedHere : row ∈ demanded) (unowned : row ∉ owned) :
    checkTargetCoverage owned demanded = .error "unowned compiler target" := by
  have missing : ¬ (∀ candidate ∈ demanded, candidate ∈ owned) :=
    fun covers => unowned (covers row demandedHere)
  simp [checkTargetCoverage, List.all_eq_true, missing]

end YuanxuProof.ModuleSystem.Building.TargetProjection
