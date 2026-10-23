-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreBuildHandoff
import YuanxuProof.Admission.CoreApprovedRecovery
namespace YuanxuProof.Admission.TestPublicationReuse

def quintSourceDigest : String := "sha256:04533fc29b327fa12d459c745bbda5a6349436fd72c2f77d27aa1c29b62a5b0e"

-- selected! owns a complete selection guard. Repeating that pure predicate
-- supplies no additional condition. This is NOT a law for arbitrary effectful
-- checker calls; source/package callbacks inside the retained guard still run.
theorem repeated_selection_predicate (selection file : Bool) :
    (selection && selection && file) = (selection && file) := by
  cases selection <;> rfl

-- The codec is pure over exact retained bytes, unlike source admission.
-- Scheme keeps the decoded packet private and checks those bytes again on
-- every explicit recovery. External atomicity is not established by this law.
theorem retained_decode {Packet : Type} (decode : String → Option Packet)
    (text : String) (packet : Packet) (decoded : decode text = some packet)
    (admit : Packet → Bool) :
    (decode text).map admit = some (admit packet) := by
  rw [decoded]
  rfl

theorem packet_reuse_rechecks_after_effect (restored files a b : Bool) :
    CoreApprovedRecovery.finish restored false true files a b = false ∧
    CoreApprovedRecovery.finish restored true false files a b = false := by
  simp [CoreApprovedRecovery.finish]

end YuanxuProof.Admission.TestPublicationReuse
