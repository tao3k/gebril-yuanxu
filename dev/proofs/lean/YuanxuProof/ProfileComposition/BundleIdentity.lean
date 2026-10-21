-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

namespace YuanxuProof.ProfileComposition.BundleIdentity

/-! Projections of `profile-bundle.ss` selection keys and duplicate checks.
Native object reference identity is supplied by the projection, not inferred
from content, a digest, a lexical alias or a caller's injectivity proposition. -/
inductive SelectionKey where
  | direct (profile : String)
  | selected (moduleDefinition instanceName profile : String)
  deriving DecidableEq, Repr

inductive Binding where
  | direct (profile : String) (objectReference : Nat)
  | selected (moduleDefinition instanceName profile revision generation : String)
  deriving DecidableEq, Repr

def Binding.key : Binding → SelectionKey
  | .direct profile _ => .direct profile
  | .selected moduleName instanceName profile _ _ => .selected moduleName instanceName profile

def compatible : Binding → Binding → Bool
  | .direct _ before, .direct _ after => before == after
  | .selected _ _ _ revision generation, .selected _ _ _ nextRevision nextGeneration =>
      revision == nextRevision && generation == nextGeneration
  | _, _ => false

inductive Conflict where
  | selectionRevision
  | distinctDirectValues
  deriving DecidableEq, Repr

/-- The first selection keeps its position and evidence. Repeats either agree
with that exact selection or fail; they never silently replace it. -/
def insert (bindings : List Binding) (candidate : Binding) : Except Conflict (List Binding) :=
  match bindings.find? (fun previous => previous.key == candidate.key) with
  | none => .ok (bindings ++ [candidate])
  | some previous =>
      if compatible previous candidate then .ok bindings
      else .error (match candidate with
        | .direct .. => .distinctDirectValues
        | .selected .. => .selectionRevision)

theorem selectedRepeatIsIdempotent (moduleName instanceName profile revision generation : String) :
    let binding := Binding.selected moduleName instanceName profile revision generation
    insert [binding] binding = .ok [binding] := by
  simp [insert, Binding.key, compatible]

theorem conflictingRevisionRejected (moduleName instanceName profile before after generation : String)
    (changed : before ≠ after) :
    insert [.selected moduleName instanceName profile before generation]
      (.selected moduleName instanceName profile after generation) = .error .selectionRevision := by
  simp [insert, Binding.key, compatible, changed]

theorem distinctDirectReferencesRejected (profile : String) (before after : Nat)
    (different : before ≠ after) :
    insert [.direct profile before] (.direct profile after) = .error .distinctDirectValues := by
  simp [insert, Binding.key, compatible, different]

#guard match insert [.selected "M" "i" "P" "r1" "g1"] (.selected "M" "i" "P" "r1" "g2") with
  | .error .selectionRevision => true
  | _ => false
#guard match insert [.direct "P" 1] (.direct "P" 2) with
  | .error .distinctDirectValues => true
  | _ => false
#guard (insert [.selected "M" "left" "P" "r1" "g1"]
  (.selected "M" "right" "P" "r1" "g1")).toOption ==
  some [.selected "M" "left" "P" "r1" "g1", .selected "M" "right" "P" "r1" "g1"]

end YuanxuProof.ProfileComposition.BundleIdentity
