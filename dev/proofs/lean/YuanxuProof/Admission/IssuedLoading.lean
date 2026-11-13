-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ArtifactClosure

namespace YuanxuProof.Admission.IssuedLoading

-- The first component of each pair comes from retained compiler-pipe
-- observations. This does not authenticate an arbitrary compiler executable.
def allows (sourceExpected sourceChecked unitsExpected unitsChecked
    snapshotExpected snapshotChecked : String) : Bool :=
  sourceExpected == sourceChecked && unitsExpected == unitsChecked &&
    snapshotExpected == snapshotChecked

theorem changed_record_refuses (s s' u u' p p' : String) (h : s ≠ s') :
    allows s s' u u' p p' = false := by simp [allows, h]

theorem changed_artifact_refuses (s s' u u' p p' : String) (h : u ≠ u') :
    allows s s' u u' p p' = false := by simp [allows, h]

theorem changed_snapshot_refuses (s s' u u' p p' : String) (h : p ≠ p') :
    allows s s' u u' p p' = false := by simp [allows, h]

theorem allowed_checks_match (s s' u u' p p' : String)
    (h : allows s s' u u' p p' = true) : s = s' ∧ u = u' ∧ p = p' := by
  simpa [allows, Bool.and_eq_true, and_assoc] using h

structure Transfer where
  issued : String
  publicBytes : String
  privateBytes : String
  deriving DecidableEq

def replacePublic (t : Transfer) (bytes : String) : Transfer :=
  {t with publicBytes := bytes}
def consume (t : Transfer) : String := t.privateBytes

theorem public_replace_preserves_consumed_bytes (t : Transfer) (bytes : String) :
    consume (replacePublic t bytes) = consume t := rfl

-- Counterexamples are explicit: byte-snapshot safety is not latest-path
-- currentness, and the private-pool authority is an environmental premise.
theorem latest_path_not_implied :
    (replacePublic ⟨"issued", "issued", "issued"⟩ "changed").publicBytes ≠
      consume (replacePublic ⟨"issued", "issued", "issued"⟩ "changed") := by decide

theorem private_writer_breaks_consumption :
    consume ⟨"issued", "issued", "changed"⟩ ≠ "issued" := by decide

end YuanxuProof.Admission.IssuedLoading
