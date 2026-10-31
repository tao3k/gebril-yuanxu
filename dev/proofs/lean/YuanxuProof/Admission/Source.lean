-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Proof.Reuse

namespace YuanxuProof.Admission.Source

/-! Source admission mirrors `admission/source.ss`: retain the actual observed
text, and recheck the same inputs before returning. Reading the filesystem and
MOP observation completeness are external boundaries; no freshness flag proves them. -/
open LeanPoo.Proof

def sourceObligation (inputs : List (String × String)) : Obligation String (fun _ => Option String) where
  dependencies := inputs.map Prod.fst
  holds := fun state => ∀ input ∈ inputs, state input.1 = some input.2
  stable := by
    intro before after same valid input member
    exact (same input.1 (List.mem_map.mpr ⟨input, member, rfl⟩)).symm.trans (valid input member)

def sourceObject (inputs : List (String × String)) (read : String → Option String) :
    ProofObject String (fun _ => Option String) :=
  { state := read, obligations := [sourceObligation inputs] }

def checkSources (inputs : List (String × String)) (read : String → Option String) : Bool :=
  inputs.all (fun input => read input.1 == some input.2)

theorem checkSources_certifies (inputs : List (String × String)) (read : String → Option String) :
    checkSources inputs read = true ↔ Certificate (sourceObject inputs read) := by
  simp [checkSources, Certificate, sourceObject, sourceObligation, List.all_eq_true]

theorem changedSourceCannotBeCertified (inputs : List (String × String))
    (read : String → Option String) (input : String × String) (member : input ∈ inputs)
    (changed : read input.1 ≠ some input.2) : ¬ Certificate (sourceObject inputs read) := by
  intro valid
  exact changed (valid (sourceObligation inputs) (by simp [sourceObject]) input member)

/-- The final check uses the final observation, including cache-hit returns.
A successful initial observation alone cannot construct the returned certificate. -/
def admitSources (inputs : List (String × String)) (before after : String → Option String) : Bool :=
  checkSources inputs before && checkSources inputs after

theorem returnCheck_certifies (inputs : List (String × String)) (before after : String → Option String)
    (accepted : admitSources inputs before after = true) :
    Certificate (sourceObject inputs after) :=
  (checkSources_certifies inputs after).mp (by
    cases initial : checkSources inputs before <;> simp_all [admitSources])

#guard admitSources [("module.ss", "old")] (fun _ => some "old") (fun _ => some "new") == false
#guard admitSources [("module.ss", "old")] (fun _ => some "old") (fun _ => some "old") == true
#guard checkSources [("module.ss", "old"), ("module.ss", "new")] (fun _ => some "old") == false

#guard checkSources [("module.ss", "")] (fun _ => none) == false

end YuanxuProof.Admission.Source
