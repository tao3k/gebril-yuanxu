-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.StoreLowering

namespace YuanxuProof.Admission.ArtifactClosure

def quintSourceDigest : String := "sha256:3fd6c0034fe2adbc0af7959aebae961389ccab96681936b71ecda58087ee9811"

-- Facts encode native-selected path, emitted/binary/metadata digests and
-- ordered dependency edges. Equality is not a proof of hash authenticity.
def admit (issued observed : String) (storesValid inputsCurrent loaded : Bool) : Bool :=
  issued == observed && storesValid && inputsCurrent && !loaded

theorem changed_closure_refuses (issued observed : String) (h : issued ≠ observed)
    (storesValid inputsCurrent loaded : Bool) :
    admit issued observed storesValid inputsCurrent loaded = false := by
  simp [admit, h]

theorem raw_store_refuses (issued observed : String) (current loaded : Bool) :
    admit issued observed false current loaded = false := by simp [admit]

theorem stale_inputs_refuse (issued observed : String) (valid loaded : Bool) :
    admit issued observed valid false loaded = false := by simp [admit]

theorem prior_loading_refuses (issued observed : String) (valid current : Bool) :
    admit issued observed valid current true = false := by simp [admit]

theorem unchanged_mediated_admits (facts : String) :
    admit facts facts true true false = true := by simp [admit]

def domainAdmit (artifacts a b : Bool) : Bool := artifacts && a && b

theorem both_requirements_preserved (artifacts a b : Bool)
    (h : domainAdmit artifacts a b = true) : a = true ∧ b = true := by
  simp only [domainAdmit, Bool.and_eq_true] at h
  exact ⟨h.1.2, h.2⟩

-- StoreLowering supplies observed callee effects; this protocol never promotes
-- the raw negative route to a certified binary. Native AST/graph extraction,
-- a trusted issuer, serial checking and stable bytes at load remain premises.
end YuanxuProof.Admission.ArtifactClosure
