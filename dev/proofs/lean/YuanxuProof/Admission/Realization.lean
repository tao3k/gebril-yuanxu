-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LeanPoo.Functional.DeclarativeMetadata
import YuanxuProof.Admission.Source

namespace YuanxuProof.Admission.Realization

inductive Disposition where
  | pureValue
  | artifactBacked
  | contextBound
  | suspendedOrUncommitted
deriving Repr, DecidableEq

inductive PortablePayload where
  | valueContent (contentIdentity : Nat)
  | artifactReference (artifactIdentity verifierEvidence : Nat)
deriving Repr, DecidableEq

def payloadKind : Disposition → Option (PortablePayload → Prop)
  | Disposition.pureValue =>
      some (fun payload =>
        match payload with
        | PortablePayload.valueContent _ => True
        | _ => False)
  | Disposition.artifactBacked =>
      some (fun payload =>
        match payload with
        | PortablePayload.artifactReference _ _ => True
        | _ => False)
  | Disposition.contextBound => none
  | Disposition.suspendedOrUncommitted => none

theorem contextBoundHasNoPortablePayload :
    payloadKind Disposition.contextBound = none := by
  rfl

theorem suspendedStateHasNoPortablePayload :
    payloadKind Disposition.suspendedOrUncommitted = none := by
  rfl

inductive PayloadCompatible : Disposition → PortablePayload → Prop where
  | pureValue
      (contentIdentity : Nat) :
      PayloadCompatible
        Disposition.pureValue
        (PortablePayload.valueContent contentIdentity)
  | artifactBacked
      (artifactIdentity verifierEvidence : Nat) :
      PayloadCompatible
        Disposition.artifactBacked
        (PortablePayload.artifactReference artifactIdentity verifierEvidence)

/-! `ops/selected-packages.ss`: validation receipts are candidate-only. The
returned package set must pass every package guard AND fresh source checks after
all validators. Effects are represented by their actual final observations. -/
open LeanPoo.Functional.DeclarativeMetadata
open LeanPoo.Proof
open YuanxuProof.Admission.Source

structure Observations where
  sources : String → Option String
  packages : String → Option String

structure Realized where
  validators : List Bool
  afterValidators : Observations

def current (sources packages : List (String × String)) (observed : Observations) : Bool :=
  checkSources sources observed.sources && checkSources packages observed.packages

def realizationCall (sources packages : List (String × String)) : Contract Unit Unit Realized where
  input := ⟨"selected package request", fun _ => True, fun _ => inferInstance⟩
  output := ⟨"all candidate admissions", fun result => result.validators.all id = true, fun _ => inferInstance⟩
  meaning := fun _ _ result => current sources packages result.afterValidators = true
  decide := fun _ _ _ => inferInstance
  rule := .atom ()

theorem returned_packages_are_current {State Error : Type} (sources packages : List (String × String))
    (execute : Unit → Except Error (Realized × State))
    (invocation : Invocation (realizationCall sources packages) execute ()) :
    Certificate (sourceObject sources invocation.result.afterValidators.sources) ∧
    Certificate (sourceObject packages invocation.result.afterValidators.packages) := by
  have checked : current sources packages invocation.result.afterValidators = true := invocation.logic
  obtain ⟨sourceCheck, packageCheck⟩ := Bool.and_eq_true_iff.mp checked
  exact ⟨(checkSources_certifies _ _).mp sourceCheck, (checkSources_certifies _ _).mp packageCheck⟩

theorem validator_package_drift_preserves_previous {State Error : Type}
    (sources packages : List (String × String)) (old tentative : State) (result : Realized)
    (execute : Unit → Except Error (Realized × State)) (called : execute () = .ok (result, tentative))
    (validated : result.validators.all id = true) (package : String × String)
    (selected : package ∈ packages) (drift : result.afterValidators.packages package.1 ≠ some package.2) :
    (realizationCall sources packages).publish old execute () = (.error .logic, old) := by
  have invalid : ¬ current sources packages result.afterValidators = true := by
    intro checked
    exact changedSourceCannotBeCertified _ _ package selected drift
      ((checkSources_certifies _ _).mp (Bool.and_eq_true_iff.mp checked).2)
  have refused := (realizationCall sources packages).invoke_logic execute () result tentative
    trivial called validated invalid
  apply (realizationCall sources packages).publish_refuses old execute () .logic
  simp [Contract.wrap, refused, Except.map]

#guard current [("config.ss", "v1")] [("provider", "digest-v1")]
  ⟨fun _ => some "v1", fun _ => some "digest-v1"⟩
#guard !current [("config.ss", "v1")] [("provider", "digest-v1")]
  ⟨fun _ => some "v1", fun _ => some "digest-v2"⟩
end YuanxuProof.Admission.Realization
