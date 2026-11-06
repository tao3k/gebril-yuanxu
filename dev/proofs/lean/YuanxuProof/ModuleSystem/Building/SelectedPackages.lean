-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Building.Inputs
import YuanxuProof.ModuleSystem.Graph.TestAdmission

/-! Reference projection for RFC 13.29. Reuses the existing discovery algorithm;
there is no runtime scheduler/cache model. `dependencies` is the actual Gerbil
expansion projection, an external correspondence obligation. Node numbers denote
observed source/context identities, not package names. No Prop-valued records. -/
namespace YuanxuProof.ModuleSystem.Building.SelectedPackages
open YuanxuProof.ModuleSystem.Graph.TestAdmission
open YuanxuProof.Admission.Source

/-- Root denotes Gerbil's declared module namespace, not a mount alias or an
absolute checkout/output path. Names are owner-relative declarations. -/
structure ScopedModuleId where
  root : Nat
  name : Nat
  deriving Repr, DecidableEq

inductive ModuleReference where
  | local (name : Nat)
  | absolute (id : ScopedModuleId)
  deriving Repr, DecidableEq

def resolveModule (owner : ScopedModuleId) : ModuleReference → ScopedModuleId
  | .local name => ⟨owner.root, name⟩
  | .absolute id => id

theorem same_name_in_distinct_roots_is_distinct (left right name : Nat)
    (distinct : left ≠ right) :
    (ScopedModuleId.mk left name) ≠ ⟨right, name⟩ := by
  intro equal
  exact distinct (congrArg ScopedModuleId.root equal)

theorem local_dependency_keeps_owner_root (owner : ScopedModuleId) (name : Nat) :
    (resolveModule owner (.local name)).root = owner.root := rfl

/-- Declaration labels are not namespace certificates. `actual` comes from
Gerbil source/header admission, an explicit implementation bridge obligation. -/
def nativeOwnerAdmitted (expected actual metadata : ScopedModuleId)
    (declared published : Nat) : Bool :=
  decide (expected = actual) && decide (expected = metadata) && decide (declared = published)

theorem native_owner_admission_binds_actual_identity
    (expected actual metadata : ScopedModuleId) (declared published : Nat)
    (accepted : nativeOwnerAdmitted expected actual metadata declared published = true) :
    expected = actual ∧ expected = metadata ∧ declared = published := by
  simpa [nativeOwnerAdmitted, Bool.and_eq_true, and_assoc] using accepted

theorem explicit_dependency_keeps_complete_id (owner target : ScopedModuleId) :
    resolveModule owner (.absolute target) = target := rfl

/-- The downstream adapter may remove only an outer always-successful
classifier with no obligations. The native Record normalizer and its exact
success/error result are retained. This does not authorize dropping callbacks
or obligations from a non-default Contract. -/
def defaultStructuralAdmission (normalize : α → Except ε α) (candidate : α) : Except ε α :=
  match normalize candidate with
  | .error failure => .error failure
  | .ok checked => .ok checked

theorem native_record_preserves_default_structural_admission
    (normalize : α → Except ε α) (candidate : α) :
    defaultStructuralAdmission normalize candidate = normalize candidate := by
  unfold defaultStructuralAdmission
  cases normalize candidate <;> rfl

/-- This models native POO slot lookup, not another scope store implementation.
Mount aliases route to complete IDs before touching those slots. -/
def projectedScope (slots : ScopedModuleId → Option Nat) (mount : Nat → Nat)
    (branch name : Nat) : Option Nat := slots ⟨mount branch, name⟩

theorem aliases_preserve_scope_identity (slots : ScopedModuleId → Option Nat)
    (mount : Nat → Nat) (left right name : Nat) (sameRoot : mount left = mount right) :
    projectedScope slots mount left name = projectedScope slots mount right name := by
  simp [projectedScope, sameRoot]

theorem missing_local_module_has_no_foreign_fallback
    (slots : ScopedModuleId → Option Nat) (owner : ScopedModuleId) (name : Nat)
    (missing : slots ⟨owner.root, name⟩ = none) :
    slots (resolveModule owner (.local name)) = none := by
  simpa [resolveModule] using missing

theorem independent_root_update_preserves_scope
    (slots : ScopedModuleId → Option Nat) (changed demanded : ScopedModuleId)
    (value : Option Nat) (differentRoots : changed.root ≠ demanded.root) :
    (fun id => if id = changed then value else slots id) demanded = slots demanded := by
  have different : demanded ≠ changed := by
    intro equal
    exact differentRoots (congrArg ScopedModuleId.root equal.symm)
  simp [different]

/-- A package window names a native package checkout, never the producer's
application init or its installed output directory. Grammar confinement and
native checkout lookup are explicit Scheme correspondence obligations. -/
inductive SourceAddress where
  | relative (parts : List String)
  | package (repository : String) (parts : List String)
  deriving Repr, DecidableEq

def resolveAddress (localRoot : List String)
    (nativeCheckout : String → Option (List String)) : SourceAddress → Option (List String)
  | .relative parts => some (localRoot ++ parts)
  | .package repository parts => (nativeCheckout repository).map (· ++ parts)

theorem package_window_uses_native_checkout (localRoot root parts : List String)
    (lookup : String → Option (List String)) (repository : String)
    (found : lookup repository = some root) :
    resolveAddress localRoot lookup (.package repository parts) = some (root ++ parts) := by
  simp [resolveAddress, found]

theorem missing_package_has_no_local_fallback (localRoot parts : List String)
    (lookup : String → Option (List String)) (repository : String)
    (missing : lookup repository = none) :
    resolveAddress localRoot lookup (.package repository parts) = none := by
  simp [resolveAddress, missing]

theorem downstream_outputs_do_not_change_source (left right root parts : List String)
    (lookup : String → Option (List String)) (repository : String)
    (found : lookup repository = some root) :
    resolveAddress left lookup (.package repository parts) =
      resolveAddress right lookup (.package repository parts) := by
  simp [resolveAddress, found]


/-- A single imported init binding cannot certify two distinct leaf owners.
Scheme resolution still obtains each leaf's owner from the selected Interface. -/
theorem init_import_cannot_certify_distinct_leaves (first second : ScopedModuleId)
    (distinct : first ≠ second) (inferred : Option ScopedModuleId)
    (firstMatch : inferred = some first) (secondMatch : inferred = some second) : False :=
  distinct (Option.some.inj (firstMatch.symm.trans secondMatch))

inductive Input where
  | source (owner : Nat) (entry : Inputs.Entry) (observations : List (String × String))
  | external (observations : List (String × String))
  | request (owner : Nat) (observations : List (String × String))
  | missing
  deriving Repr, DecidableEq

def observations : Input → List (String × String)
  | .source _ _ rows | .external rows | .request _ rows => rows
  | .missing => []

def eligible (owners : List Nat) : Input → Bool
  | .source owner _ _ | .request owner _ => owners.contains owner
  | .external _ => true
  | .missing => false

def sourceEntry : Input → Option Inputs.Entry
  | .source _ entry _ => some entry
  | _ => none

def requestNode (input : Input) : Bool :=
  match input with | .request _ _ => true | _ => false

def targets (describe : Nat → Input) (nodes : List Nat) : List Inputs.Entry :=
  nodes.filterMap (fun node => sourceEntry (describe node))

def footprint (describe : Nat → Input) (nodes : List Nat) : List (String × String) :=
  nodes.flatMap (fun node => observations (describe node))

def compatible (left right : Inputs.Entry) : Bool :=
  left.compilerIdentity != right.compilerIdentity ||
    (left.path == right.path && left.options == right.options &&
      left.compilerForms == right.compilerForms)

def consistent (entries : List Inputs.Entry) : Bool :=
  entries.all (fun left => entries.all (compatible left))

inductive Failure where
  | unfinished | undeclaredOrMissing | compilerConflict
  deriving Repr, DecidableEq

/-- Completeness is checked before returning any plan. Fuel exhaustion is a
failure, never a smaller successful closure. External requests remain in `nodes`;
they are not implicitly executed or mistaken for native Scheme targets. -/
def prepare (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) : Except Failure (List Nat) :=
  let state := discover dependencies fuel ⟨[], roots⟩
  if state.pending != [] then .error .unfinished
  else if !(state.seen.all (fun node => eligible owners (describe node))) then
    .error .undeclaredOrMissing
  else if !(consistent (targets describe state.seen)) then .error .compilerConflict
  else .ok state.seen

/-- Tags select roots across all declared source windows, independently of the
dependency graph. A window without matching roots still contributes eligible
owners; it cannot implicitly turn every owner into a selected root. -/
def categoryRoots (tag : Nat) (windows : List (List (Nat × List Nat))) : List Nat :=
  windows.flatMap fun rows => (rows.filter fun row => row.2.contains tag).map Prod.fst

theorem dependency_only_window_keeps_roots (tag : Nat)
    (windows : List (List (Nat × List Nat))) (auxiliary : List (Nat × List Nat))
    (noMatches : auxiliary.filter (fun row => row.2.contains tag) = []) :
    categoryRoots tag (windows ++ [auxiliary]) = categoryRoots tag windows := by
  simp only [categoryRoots, List.flatMap_append, List.flatMap_cons,
    List.flatMap_nil, noMatches, List.map_nil, List.append_nil]

/-- The ordinary dependency closure remains authoritative for all consumers.
Auxiliary-window tags neither drop dependency nodes nor add compile roots. -/
theorem dependency_only_window_keeps_projection (tag : Nat)
    (windows : List (List (Nat × List Nat))) (auxiliary : List (Nat × List Nat))
    (noMatches : auxiliary.filter (fun row => row.2.contains tag) = [])
    (dependencies : Nat → List Nat) (owners : List Nat) (describe : Nat → Input) (fuel : Nat) :
    prepare dependencies (categoryRoots tag (windows ++ [auxiliary])) owners describe fuel =
      prepare dependencies (categoryRoots tag windows) owners describe fuel := by
  rw [dependency_only_window_keeps_roots tag windows auxiliary noMatches]

#guard categoryRoots 7 [[(0, [7])], [(1, [9]), (2, [10]), (3, [11])]] == [0]

theorem successful_projection (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes) :
    nodes = (discover dependencies fuel ⟨[], roots⟩).seen ∧
    (discover dependencies fuel ⟨[], roots⟩).pending = [] ∧
    nodes.all (fun node => eligible owners (describe node)) = true ∧
    consistent (targets describe nodes) = true := by
  unfold prepare at ok
  dsimp only at ok
  split at ok
  · contradiction
  · rename_i finished
    split at ok
    · contradiction
    · rename_i eligibleInputs
      split at ok
      · contradiction
      · rename_i consistentInputs
        cases ok
        exact ⟨rfl, by simpa using finished,
          by simpa using eligibleInputs, by simpa using consistentInputs⟩

theorem successful_closure_exact (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes) (node : Nat) :
    node ∈ nodes ↔ Demanded dependencies roots node := by
  rcases successful_projection dependencies roots owners describe fuel nodes ok with
    ⟨same, finished, _⟩
  rw [same]
  exact completed_discovery_exact dependencies roots fuel finished node

theorem successful_target_iff (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes) (entry : Inputs.Entry) :
    entry ∈ targets describe nodes ↔
      ∃ node, Demanded dependencies roots node ∧ sourceEntry (describe node) = some entry := by
  simp only [targets, List.mem_filterMap]
  constructor
  · rintro ⟨node, member, source⟩
    exact ⟨node, (successful_closure_exact dependencies roots owners describe fuel nodes ok node).mp member,
      source⟩
  · rintro ⟨node, demanded, source⟩
    exact ⟨node, (successful_closure_exact dependencies roots owners describe fuel nodes ok node).mpr demanded,
      source⟩

theorem source_owner_declared (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes)
    (node owner : Nat) (entry : Inputs.Entry) (rows : List (String × String))
    (member : node ∈ nodes) (source : describe node = .source owner entry rows) : owner ∈ owners := by
  have checked := (successful_projection dependencies roots owners describe fuel nodes ok).2.2.1
  have valid := List.all_eq_true.mp checked node member
  simpa [source, eligible] using valid

theorem unreachable_source_not_compiled (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes) (node : Nat)
    (unreachable : ¬ Demanded dependencies roots node) : node ∉ nodes := by
  exact fun member => unreachable
    ((successful_closure_exact dependencies roots owners describe fuel nodes ok node).mp member)

theorem foreign_source_preserved (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes)
    (node owner : Nat) (entry : Inputs.Entry) (rows : List (String × String))
    (demanded : Demanded dependencies roots node)
    (source : describe node = .source owner entry rows) : entry ∈ targets describe nodes := by
  apply (successful_target_iff dependencies roots owners describe fuel nodes ok entry).mpr
  exact ⟨node, demanded, by simp [source, sourceEntry]⟩

/-- The complete selected support remains above. A package's native Make
inventory is only an ownership partition of that support, not a new closure.
Filtering retains the actual Entry, including its original source path. -/
def packageTargets (owned : Inputs.Entry → Bool) (entries : List Inputs.Entry) :=
  entries.filter owned

theorem package_target_exact (owned : Inputs.Entry → Bool)
    (entries : List Inputs.Entry) (entry : Inputs.Entry) :
    entry ∈ packageTargets owned entries ↔ entry ∈ entries ∧ owned entry = true := by
  simp [packageTargets]

theorem package_partition_complete (owned : Inputs.Entry → Bool)
    (entries : List Inputs.Entry) (entry : Inputs.Entry) (present : entry ∈ entries) :
    entry ∈ packageTargets owned entries ∨
      entry ∈ packageTargets (fun value => !(owned value)) entries := by
  cases same : owned entry <;> simp [packageTargets, present, same]

theorem package_partition_disjoint (owned : Inputs.Entry → Bool)
    (entries : List Inputs.Entry) (entry : Inputs.Entry)
    (localTarget : entry ∈ packageTargets owned entries) :
    entry ∉ packageTargets (fun value => !(owned value)) entries := by
  have checked := (package_target_exact owned entries entry).mp localTarget
  simp [packageTargets, checked.2]

/-- Package partitions name/schedule the same source set. They do not classify
foreign selected sources as installed prerequisites. Entry values stay intact. -/
theorem package_reassembly_exact (owned : Inputs.Entry → Bool)
    (entries : List Inputs.Entry) (entry : Inputs.Entry) :
    entry ∈ packageTargets owned entries ++
      packageTargets (fun value => !(owned value)) entries ↔ entry ∈ entries := by
  simp only [List.mem_append, package_target_exact]
  cases same : owned entry <;> simp [same]

theorem installed_input_has_no_source_target (rows : List (String × String)) :
    sourceEntry (.external rows) = none := by rfl

theorem selected_source_is_target (describe : Nat → Input) (nodes : List Nat)
    (node owner : Nat) (entry : Inputs.Entry) (rows : List (String × String))
    (member : node ∈ nodes) (source : describe node = .source owner entry rows) :
    entry ∈ targets describe nodes := by
  exact List.mem_filterMap.mpr ⟨node, member, by simp [source, sourceEntry]⟩

/-- The foreign partition is still an actual compile obligation. Dropping it
violates exactness even when a same-named artifact happens to be installed. -/
theorem foreign_partition_cannot_be_dropped (owned : Inputs.Entry → Bool)
    (entries : List Inputs.Entry) (entry : Inputs.Entry)
    (present : entry ∈ entries) (foreignSource : owned entry = false) :
    entry ∈ packageTargets (fun value => !(owned value)) entries ∧
      entry ∉ packageTargets owned entries := by
  simp [packageTargets, present, foreignSource]

theorem successful_targets_compatible (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (nodes : List Nat)
    (ok : prepare dependencies roots owners describe fuel = .ok nodes)
    (left right : Inputs.Entry) (l : left ∈ targets describe nodes)
    (r : right ∈ targets describe nodes) : compatible left right = true := by
  have checked := (successful_projection dependencies roots owners describe fuel nodes ok).2.2.2
  exact List.all_eq_true.mp (List.all_eq_true.mp checked left l) right r

/-- Structural planning is not permission to publish. Uses actual source reads
at both boundaries and enumerates every selected external request completion.
Request identity, realization correctness and read atomicity remain native duties. -/
def publicationReady (describe : Nat → Input) (nodes : List Nat)
    (realized : List Nat) (before after : String → Option String) : Bool :=
  admitSources (footprint describe nodes) before after &&
    nodes.all (fun node => !requestNode (describe node) || realized.contains node)

theorem publication_sources_current (describe : Nat → Input) (nodes realized : List Nat)
    (before after : String → Option String)
    (accepted : publicationReady describe nodes realized before after = true) :
    checkSources (footprint describe nodes) after = true := by
  simp only [publicationReady, admitSources, Bool.and_eq_true] at accepted
  exact accepted.1.2

theorem missing_realization_refused (describe : Nat → Input) (nodes realized : List Nat)
    (before after : String → Option String) (node : Nat) (member : node ∈ nodes)
    (request : requestNode (describe node) = true) (missing : node ∉ realized) :
    publicationReady describe nodes realized before after = false := by
  have failed : nodes.all (fun n => !requestNode (describe n) || realized.contains n) ≠ true := by
    intro checked
    have this := List.all_eq_true.mp checked node member
    simp [request, missing] at this
  unfold publicationReady
  rw [Bool.eq_false_iff.mpr failed]
  simp

/-- Join structural completeness and final observation checks. An empty or
otherwise locally-current footprint cannot bypass a refused structural plan. -/
def admitBuild (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (realized : List Nat)
    (before after : String → Option String) : Bool :=
  match prepare dependencies roots owners describe fuel with
  | .error _ => false
  | .ok nodes => publicationReady describe nodes realized before after

theorem admitted_build_has_complete_plan (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (realized : List Nat)
    (before after : String → Option String)
    (accepted : admitBuild dependencies roots owners describe fuel realized before after = true) :
    ∃ nodes, prepare dependencies roots owners describe fuel = .ok nodes ∧
      publicationReady describe nodes realized before after = true := by
  unfold admitBuild at accepted
  split at accepted
  · contradiction
  · rename_i nodes prepared
    exact ⟨nodes, prepared, accepted⟩

theorem refused_plan_cannot_publish (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (realized : List Nat)
    (before after : String → Option String) (failure : Failure)
    (refused : prepare dependencies roots owners describe fuel = .error failure) :
    admitBuild dependencies roots owners describe fuel realized before after = false := by
  simp [admitBuild, refused]

theorem admitted_build_contains_foreign_source (dependencies : Nat → List Nat) (roots owners : List Nat)
    (describe : Nat → Input) (fuel : Nat) (realized : List Nat)
    (before after : String → Option String)
    (accepted : admitBuild dependencies roots owners describe fuel realized before after = true)
    (node owner : Nat) (entry : Inputs.Entry) (rows : List (String × String))
    (demanded : Demanded dependencies roots node)
    (source : describe node = .source owner entry rows) :
    ∃ nodes, prepare dependencies roots owners describe fuel = .ok nodes ∧
      entry ∈ targets describe nodes ∧ checkSources (footprint describe nodes) after = true := by
  obtain ⟨nodes, prepared, ready⟩ := admitted_build_has_complete_plan
    dependencies roots owners describe fuel realized before after accepted
  exact ⟨nodes, prepared,
    foreign_source_preserved dependencies roots owners describe fuel nodes prepared node owner entry rows
      demanded source,
    publication_sources_current describe nodes realized before after ready⟩

/-- A native adapter must prove its output key correspondence. Environment
separation is not a claim that two paths aliasing one directory are isolated. -/
structure Product where
  input : Inputs.Entry
  revision : String
  toolchain : String
  deriving Repr, DecidableEq

abbrev Store := Nat → String → Option Product

def install (store : Store) (environment : Nat) (product : Product) : Store :=
  fun target identity =>
    if target = environment ∧ identity = product.input.compilerIdentity then some product
    else store target identity

def clean (store : Store) (environment : Nat) (identities : List String) : Store :=
  fun target identity =>
    if target = environment ∧ identity ∈ identities then none else store target identity

theorem install_identity_preserved (store : Store) (environment : Nat) (product : Product) :
    install store environment product environment product.input.compilerIdentity = some product := by
  simp [install]

theorem install_other_environment (store : Store) (environment other : Nat)
    (product : Product) (different : other ≠ environment) (identity : String) :
    install store environment product other identity = store other identity := by
  simp [install, different]

theorem clean_other_environment (store : Store) (environment other : Nat)
    (identities : List String) (different : other ≠ environment) (identity : String) :
    clean store environment identities other identity = store other identity := by
  simp [clean, different]

theorem clean_unowned_product (store : Store) (environment : Nat)
    (identities : List String) (identity : String) (unowned : identity ∉ identities) :
    clean store environment identities environment identity = store environment identity := by
  simp [clean, unowned]

/- Executable controls are model examples, not runtime/downstream receipts. -/
def exampleEntry (identity : String) : Inputs.Entry :=
  ⟨"/upstream/" ++ identity ++ ".ss", identity, "source", [], ["body"]⟩

/-- One deployment root reaches owners in both packages despite their distinct
categories. The dependency-only window contributes no extra roots. -/
example : prepare (fun n => if n = 0 then [1, 2, 3] else [])
    (categoryRoots 7 [[(0, [7]), (1, [9])], [(2, [10]), (3, [11])]])
    [10, 20]
    (fun n => .source (if n < 2 then 10 else 20) (exampleEntry (toString n)) [])
    12 = .ok [3, 2, 1, 0] := by rfl

def exampleDeps : Nat → List Nat
  | 0 => [1, 2]
  | 1 => [2]
  | _ => []

def exampleInput : Nat → Input
  | 0 => .source 10 (exampleEntry "lab/module") [("lab.ss", "v1")]
  | 1 => .source 20 (exampleEntry "community/helper") [("helper.ss", "v2")]
  | 2 => .external [("gerbil-core.ssi", "gerbil")]
  | _ => .missing

example : prepare exampleDeps [0] [10, 20] exampleInput 8 = .ok [2, 1, 0] := by rfl
example : prepare exampleDeps [0] [10, 20] exampleInput 1 = .error .unfinished := by rfl
example : prepare exampleDeps [0] [10] exampleInput 8 = .error .undeclaredOrMissing := by rfl
#guard (targets exampleInput [2, 1, 0]).map Inputs.Entry.compilerIdentity ==
  ["community/helper", "lab/module"]
example : prepare exampleDeps [0] [10, 20] (fun n => if n = 1 then .missing else exampleInput n) 8 =
  .error .undeclaredOrMissing := by rfl
example : prepare exampleDeps [0] [10, 20]
  (fun n => if n = 1 then .source 20
    { exampleEntry "lab/module" with path := "/different.ss" } [] else exampleInput n) 8 =
  .error .compilerConflict := by rfl
#guard publicationReady exampleInput [2, 1, 0] []
  (fun path => if path = "lab.ss" then some "v1" else if path = "helper.ss" then some "v2" else some "sdk")
  (fun _ => some "changed") == false
#guard publicationReady (fun _ => .request 10 []) [0] [] (fun _ => none) (fun _ => none) == false
#guard publicationReady (fun _ => .request 10 []) [0] [0] (fun _ => none) (fun _ => none) == true
#guard admitBuild exampleDeps [0] [10, 20] exampleInput 1 []
  (fun _ => none) (fun _ => none) == false
#guard admitBuild (fun _ => []) [0] [10] (fun _ => .missing) 2 []
  (fun _ => none) (fun _ => none) == false

end YuanxuProof.ModuleSystem.Building.SelectedPackages
