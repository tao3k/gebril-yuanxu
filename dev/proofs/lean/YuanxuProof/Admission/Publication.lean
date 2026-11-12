-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.Source
import LeanPoo.Functional.DeclarativeMetadata

namespace YuanxuProof.Admission.Publication
open LeanPoo.Proof
open YuanxuProof.Admission.Source

/-! The published-contract branch of `admission/publication.ss:schema-observations`.
Normalization is the actual parser/normalizer boundary: its observed result is
an input, not an assumed equality. Object reference IDs model `eq?`, not hashes. -/
structure SchemaAssociation where
  artifactValid : Bool
  diagnostics : List String
  selectedNode : Nat
  artifactNode : Nat
  selectedNormalization : List (String × String)
  artifactNormalization : List (String × String)
  inputs : List (String × String)
  deriving Repr, DecidableEq

def associationMatches (a : SchemaAssociation) : Bool :=
  a.artifactValid && a.diagnostics.isEmpty && (a.selectedNode == a.artifactNode) &&
  (a.selectedNormalization == a.artifactNormalization) && !a.inputs.isEmpty &&
  a.inputs.all (fun input => input.1.startsWith "/")

def associationObligation (a : SchemaAssociation) : Obligation String (fun _ => Option String) where
  dependencies := []
  holds := fun _ => associationMatches a = true
  stable := fun _ _ _ proof => proof

/-- Source observations and artifact association are owned by ONE proof object;
adding an association cannot erase the source obligations. -/
def publicationObject (a : SchemaAssociation) (read : String → Option String) :=
  (sourceObject a.inputs read).withObligation (associationObligation a)

def checkPublication (a : SchemaAssociation) (read : String → Option String) : Bool :=
  checkSources a.inputs read && associationMatches a

theorem check_certifies (a : SchemaAssociation) (read : String → Option String) :
    checkPublication a read = true ↔ Certificate (publicationObject a read) := by
  simp [checkPublication, publicationObject, ProofObject.withObligation, Certificate,
    sourceObject, associationObligation, sourceObligation, checkSources, List.all_eq_true]

def admit (a : SchemaAssociation) (read : String → Option String) :
    Option { object : ProofObject String (fun _ => Option String) // Certificate object } :=
  if checked : checkPublication a read = true then
    some ⟨publicationObject a read, (check_certifies a read).mp checked⟩
  else none

theorem publication_has_current_sources (a : SchemaAssociation) (read : String → Option String)
    (checked : checkPublication a read = true) : Certificate (sourceObject a.inputs read) := by
  exact (checkSources_certifies _ _).mp (show checkSources a.inputs read = true from (Bool.and_eq_true_iff.mp checked).1)

theorem mismatched_schema_rejected (a : SchemaAssociation) (read : String → Option String)
    (different : a.selectedNormalization ≠ a.artifactNormalization) : admit a read = none := by
  simp [admit, checkPublication, associationMatches, different]

theorem wrong_node_rejected (a : SchemaAssociation) (read : String → Option String)
    (different : a.selectedNode ≠ a.artifactNode) : admit a read = none := by
  simp [admit, checkPublication, associationMatches, different]

theorem changed_source_rejected (a : SchemaAssociation) (read : String → Option String)
    (input : String × String) (member : input ∈ a.inputs) (changed : read input.1 ≠ some input.2) :
    admit a read = none := by
  have failed : checkSources a.inputs read ≠ true := fun checked =>
    changedSourceCannotBeCertified _ _ input member changed ((checkSources_certifies _ _).mp checked)
  simp [admit, checkPublication, Bool.eq_false_iff.mpr failed]

open LeanPoo.Functional.DeclarativeMetadata

/-- Projection of the admitted Core evidence and the RETURN-time source view.
The read function is an observed input; no filesystem or atomicity is postulated. -/
structure ReturnedEvidence where
  accepted : Bool
  read : String → Option String

/-- Use the same public metadata contract mechanism as `publish-current`.
Dependent meaning is evaluated after the source returns its tentative state. -/
def publicationCall : Contract Unit SchemaAssociation ReturnedEvidence where
  input := ⟨"configuration association", fun _ => True, fun _ => inferInstance⟩
  output := ⟨"accepted Core evidence", fun evidence => evidence.accepted = true, fun _ => inferInstance⟩
  meaning := fun _ association evidence => checkPublication association evidence.read = true
  decide := fun _ _ _ => inferInstance
  rule := .atom ()

theorem returned_invocation_certifies {State Error : Type} (a : SchemaAssociation)
    (execute : SchemaAssociation → Except Error (ReturnedEvidence × State))
    (invocation : Invocation publicationCall execute a) :
    Certificate (publicationObject a invocation.result.read) :=
  (check_certifies _ _).mp invocation.logic

/-- Even accepted Core output cannot publish a tentative state after source
change. This derives the refusal from bytes and the dependency's invoke/publish
operations, rather than accepting a refusal/atomicity witness as a premise. -/
theorem stale_return_keeps_previous {State Error : Type} (old tentative : State)
    (a : SchemaAssociation) (evidence : ReturnedEvidence)
    (execute : SchemaAssociation → Except Error (ReturnedEvidence × State))
    (called : execute a = .ok (evidence, tentative)) (accepted : evidence.accepted = true)
    (input : String × String) (member : input ∈ a.inputs)
    (changed : evidence.read input.1 ≠ some input.2) :
    publicationCall.publish old execute a = (.error .logic, old) := by
  have invalid : ¬ checkPublication a evidence.read = true := by
    intro checked
    exact changedSourceCannotBeCertified _ _ input member changed
      (publication_has_current_sources _ _ checked)
  have refused := publicationCall.invoke_logic execute a evidence tentative trivial called accepted invalid
  apply publicationCall.publish_refuses old execute a .logic
  simp [Contract.wrap, refused, Except.map]

private def exampleAssociation : SchemaAssociation :=
  ⟨true, [], 7, 7, [("type", "string")], [("type", "string")], [("/schema.json", "source")]⟩
#guard checkPublication exampleAssociation (fun _ => some "source")
#guard !checkPublication {exampleAssociation with artifactNode := 8} (fun _ => some "source")
#guard !checkPublication {exampleAssociation with inputs := []} (fun _ => some "source")
#guard !checkPublication {exampleAssociation with diagnostics := ["invalid"]} (fun _ => some "source")
#guard !checkPublication exampleAssociation (fun _ => some "changed")
end YuanxuProof.Admission.Publication
