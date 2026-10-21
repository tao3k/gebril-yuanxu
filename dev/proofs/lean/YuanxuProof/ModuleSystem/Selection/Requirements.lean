-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.Absence
import LeanPoo.Functional.CertifiedRequirements


namespace YuanxuProof.ModuleSystem.Selection.Requirements

open LeanPoo.Functional
open LeanPoo.Functional.Requirements

/-- Every successfully resolved capability has an ancestor in the supplied C4
snapshot. No loaded-module registry or filesystem discovery participates. -/
theorem resolvedCapabilitiesHaveDeclaredOrigin
    {Context Key : Type} {Value : Context → Key → Type}
    (order : LeanPoo.C4.VerifiedOrder graph root)
    (providers : String → Provider Context Key Value) (keys : List Key)
    (factories : Factories Context Value keys)
    (resolved : prepare (assemble order providers) keys = .ok factories)
    (key : Key) (required : key ∈ keys) :
    ∃ name, LeanPoo.C4.Ancestor graph name root ∧
      ∃ factory, providers name key = some factory :=
  prepare_origin order providers keys factories resolved key required

/-- Admitted absence is a checked negative capability certificate, not a tag
which can be supplied alongside an actually present contribution. -/
theorem admittedAbsenceCannotHaveProvider
    {Context Key : Type} {Value : Context → Key → Type}
    {provider : Provider Context Key Value} {keys : List Key}
    (absence : AbsenceCertificate provider keys) (key : Key) (required : key ∈ keys)
    (factory : Factory Context (fun c => Value c key)) :
    provider key ≠ some factory := by
  rw [absence.absent key required]
  simp

end YuanxuProof.ModuleSystem.Selection.Requirements
