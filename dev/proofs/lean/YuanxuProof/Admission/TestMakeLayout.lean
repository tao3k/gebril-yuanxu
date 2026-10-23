-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.CoreApprovedRecovery
namespace YuanxuProof.Admission.TestMakeLayout

def quintSourceDigest : String := "sha256:9309a7f2d07f1573797bb884d921b67fac282f0727c3f5c2897ad5b5a69ca5cd"

-- Sanitized path components. Scheme's existing identity/path admission must
-- establish this extraction; these lists do not model symlinks or host I/O.
structure Target where
  absolute : Bool
  components : List String
  deriving DecidableEq

def resolve (base : List String) (target : Target) : List String :=
  if target.absolute then target.components else base ++ target.components

-- The producer uses the module identity; std/make predicts output from target.
theorem root_relative_matches_producer (library namespacePrefix nested leaf : List String) :
    resolve (library ++ namespacePrefix) ⟨false, nested ++ leaf⟩ =
      library ++ (namespacePrefix ++ nested ++ leaf) := by
  simp [resolve, List.append_assoc]

theorem absolute_discards_library_root (library namespacePrefix source : List String) :
    resolve (library ++ namespacePrefix) ⟨true, source⟩ = source := by
  rfl

theorem absolute_misses_owned_product (library namespacePrefix source identity : List String)
    (separate : source ≠ library ++ identity) :
    resolve (library ++ namespacePrefix) ⟨true, source⟩ ≠ library ++ identity := by
  simpa [resolve] using separate

-- Finite work projection of native build?/build-dependent?. Correct paths
-- alone are insufficient: stable source/dependency timestamps are a premise.
def nativeWork (roots : Nat) (outputsPresent sourcesStable dependenciesStable : Bool) : Nat :=
  if outputsPresent && sourcesStable && dependenciesStable then 0 else roots

theorem warm_zero_work (roots : Nat) : nativeWork roots true true true = 0 := by
  simp [nativeWork]
theorem missing_output_rebuilds (roots : Nat) (sourcesStable dependenciesStable : Bool) :
    nativeWork roots false sourcesStable dependenciesStable = roots := by
  simp [nativeWork]

-- Fixing layout leaves the actual admission predicates unchanged.
theorem layout_does_not_waive_source (restored approval files a b : Bool) :
    CoreApprovedRecovery.finish restored approval false files a b = false := by
  exact CoreApprovedRecovery.changed_source_refused restored approval files a b

theorem layout_preserves_both_requirements
    (restored approval source files a b : Bool)
    (accepted : CoreApprovedRecovery.finish restored approval source files a b = true) :
    a = true ∧ b = true := by
  exact ⟨(CoreApprovedRecovery.accepted_preserves_boundaries
    restored approval source files a b accepted).2.2.2.1,
    (CoreApprovedRecovery.accepted_preserves_boundaries
    restored approval source files a b accepted).2.2.2.2⟩

end YuanxuProof.Admission.TestMakeLayout
