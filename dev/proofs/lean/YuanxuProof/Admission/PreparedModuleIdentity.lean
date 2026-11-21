-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean

namespace YuanxuProof.Admission.PreparedModuleIdentity

-- These inputs must account for Gerbil's reader, resolution and package
-- context as well as the source bytes. Equal file bytes alone are insufficient.
variable {Inputs Identity : Type} [DecidableEq Identity]

structure Prepared (Inputs Identity : Type) where
  inputs : Inputs
  identity : Identity

inductive Refusal where
  | nativeIdentity | declarationIdentity
  deriving DecidableEq

def check (native declared owner expected : Identity) : Except Refusal Unit :=
  if native ≠ expected then .error .nativeIdentity
  else if declared ≠ owner then .error .declarationIdentity else .ok ()

def admit (resolve : Inputs → Identity) (live : Inputs)
    (prepared : Option (Prepared Inputs Identity)) (declared owner expected : Identity) :
    Except Refusal Unit :=
  check (match prepared with
         | some evidence => evidence.identity
         | none => resolve live) declared owner expected

theorem prepared_preserves_admission (resolve : Inputs → Identity)
    (live : Inputs) (prepared : Prepared Inputs Identity) (declared owner expected : Identity)
    (issued : prepared.identity = resolve prepared.inputs)
    (current : live = prepared.inputs) :
    admit resolve live (some prepared) declared owner expected =
      admit resolve live none declared owner expected := by
  simp [admit, issued, current]

theorem native_refusal_precedes_declaration (native declared owner expected : Identity)
    (changed : native ≠ expected) :
    check native declared owner expected = .error .nativeIdentity := by
  simp [check, changed]

-- An expansion or author action may change the effective native identity.
-- A prior match cannot justify reusing the preparation across that effect.
theorem changed_after_effect (resolve : Inputs → Identity)
    (before after : Inputs) (expected : Identity)
    (old : resolve before = expected) (changed : resolve after ≠ expected) :
    admit resolve after (some ⟨before, resolve before⟩) expected expected expected = .ok () ∧
    admit resolve after none expected expected expected = .error .nativeIdentity := by
  simp [admit, check, old, changed]

end YuanxuProof.Admission.PreparedModuleIdentity
