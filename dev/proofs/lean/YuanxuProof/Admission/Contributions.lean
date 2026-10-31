-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation
import YuanxuProof.Admission.Source

namespace YuanxuProof.Admission.Contributions
open LeanPoo.Functional

/-! `admission/contributions.ss:coverage!`: exact row identities, selected
record/source/publication, owner/key, generation, path and resolved payload.
References are native object identities, not equal-looking content/digests. -/
structure Origin where
  record : Nat
  source : Nat
  publication : Nat
  owner : String
  key : String
  generation : String
  path : List String
  deriving Repr, DecidableEq

structure Row where
  reference : Nat
  origin : Origin
  payload : Nat
  deriving Repr, DecidableEq

structure Selected where
  origin : Origin
  resolvedPayload : Nat
  deriving Repr, DecidableEq

inductive Failure where
  | incomplete | substitutedOrigin | substitutedPayload
  deriving Repr, DecidableEq

/-- The selected side is recomputed from the actual current selected record
and export-path walk; it is not a user-provided 'origin authenticated' flag. -/
def checkRow (selected : Selected) (registered row : Row) : Except Failure Row :=
  if row.reference ≠ registered.reference ∨ row.origin ≠ selected.origin then .error .substitutedOrigin
  else if row.payload ≠ selected.resolvedPayload then .error .substitutedPayload
  else .ok row

def coverage (selected : List Selected) (registered rows : List Row) : Except Failure (List Row) :=
  if selected.length = rows.length ∧ registered.length = rows.length then
    Validation.traverse (fun entry => checkRow entry.1.1 entry.1.2 entry.2) ((selected.zip registered).zip rows)
  else .error .incomplete

theorem accepted_row_exact (selected : Selected) (registered row output : Row)
    (accepted : checkRow selected registered row = .ok output) :
    row.reference = registered.reference ∧ row.origin = selected.origin ∧
      row.payload = selected.resolvedPayload ∧ output = row := by
  unfold checkRow at accepted
  split at accepted
  · contradiction
  · rename_i same
    split at accepted
    · contradiction
    · rename_i payload
      have refs : row.reference = registered.reference ∧ row.origin = selected.origin := by simpa using same
      have value : row.payload = selected.resolvedPayload := by simpa using payload
      exact ⟨refs.1, refs.2, value, (Except.ok.inj accepted).symm⟩

theorem missing_rows_refused (selected : List Selected) (registered rows : List Row)
    (missing : selected.length ≠ rows.length) : coverage selected registered rows = .error .incomplete := by
  simp [coverage, missing]

theorem different_reference_refused (selected : Selected) (registered row : Row)
    (substituted : row.reference ≠ registered.reference) :
    checkRow selected registered row = .error .substitutedOrigin := by simp [checkRow, substituted]

/-- Source currentness remains a separate checked obligation; passing coverage
never certifies a source snapshot by itself. -/
def checkedCoverage (inputs : List (String × String)) (selected : List Selected)
    (registered rows : List Row) : Factory (String → Option String) (fun _ => Except Failure (List Row)) :=
  Factory.choose (Source.checkSources inputs) (fun _ => coverage selected registered rows)
    (fun _ => .error .incomplete)

private def origin : Origin := ⟨1, 2, 3, "owner", "route", "g1", ["export"]⟩
#guard (coverage [⟨origin, 4⟩] [⟨5, origin, 4⟩] [⟨5, origin, 4⟩]).toOption.isSome
#guard !(coverage [⟨origin, 4⟩] [⟨5, origin, 4⟩] [⟨6, origin, 4⟩]).toOption.isSome
#guard !(coverage [⟨origin, 4⟩] [⟨5, origin, 4⟩] [⟨5, origin, 9⟩]).toOption.isSome
#guard !(coverage [⟨origin, 4⟩] [⟨5, origin, 4⟩] []).toOption.isSome
end YuanxuProof.Admission.Contributions
