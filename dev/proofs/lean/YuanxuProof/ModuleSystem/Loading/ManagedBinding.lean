-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Loading.MetadataProjection
import LeanPoo.Functional.StatefulValidation

/-! After declaration-graph admission: pending handles are not admitted scopes.
Scope materialization preserves the existing complete requirement boundary.
State is concrete post-callback data; there are no author-supplied purity flags.
Native source/owner extraction and graph admission remain correspondence duties. -/
namespace YuanxuProof.ModuleSystem.Loading.ManagedBinding
open LeanPoo.Functional
open MetadataProjection

structure Stamp where
  owner : String
  revision : Nat
  deriving DecidableEq, Repr

structure World where
  generation : Nat
  selected : List String
  disabled : List String
  sources : List (String × Nat)
  deriving DecidableEq, Repr

structure Handle where
  metadata : Metadata
  generation : Nat
  source : Stamp
  deriving DecidableEq, Repr

structure Scope where
  receiver : Nat
  port : Nat
  deriving DecidableEq, Repr

structure Materialized where
  source : Stamp
  value : Scope
  deriving DecidableEq, Repr

structure Binding where
  dependency : Dependency
  source : Stamp
  candidate : Scope
  deriving DecidableEq, Repr

structure Admission where
  candidate : Scope
  dependencies : List Binding
  deriving DecidableEq, Repr

abbrev Action (Value : Type) := World → Except String Value × World

def pending (metadata : Metadata) (generation revision : Nat) : Handle :=
  ⟨metadata, generation, ⟨metadata.identity, revision⟩⟩

def eligible (world : World) (owner : String) : Bool :=
  world.selected.contains owner && !world.disabled.contains owner

def stampCurrent (world : World) (stamp : Stamp) : Bool :=
  eligible world stamp.owner && world.sources.lookup stamp.owner == some stamp.revision

def ready (handle : Handle) (world : World) : Bool :=
  handle.generation == world.generation &&
  handle.source.owner == handle.metadata.identity && stampCurrent world handle.source &&
  handle.metadata.dependencies.all (fun dependency => eligible world dependency.target)

def checkRequirement (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope) (world : World) (dependency : Dependency) :
    Except String Binding × World :=
  if !eligible world dependency.target then (.error "provider unavailable", world)
  else
    let (resolved, afterResolve) := resolve dependency.target world
    match resolved with
    | .error cause => (.error cause, afterResolve)
    | .ok provider =>
      if provider.source.owner != dependency.target then
        (.error "provider owner mismatch", afterResolve)
      else
        let (checked, afterCheck) := check dependency provider.value afterResolve
        -- The source stamp predates normalization. A callback cannot rebaseline
        -- it by returning a different checked value or receiver identity.
        (checked.map (fun candidate => ⟨dependency, provider.source, candidate⟩), afterCheck)

def returnScope (handle : Handle) (bindings : List Binding) (candidate : Scope)
    (world : World) : Except String Admission × World :=
  if ready handle world && bindings.all (fun binding => stampCurrent world binding.source) then
    (.ok ⟨candidate, bindings⟩, world)
  else (.error "stale scope sources", world)

def materialize (handle : Handle) (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope)
    (world : World) : Except String Admission × World :=
  if !ready handle world then (.error "selection unavailable or stale", world)
  else
    let (requirements, afterRequirements) :=
      Validation.traverseState (checkRequirement resolve check) world handle.metadata.dependencies
    match requirements with
    | .error cause => (.error cause, afterRequirements)
    | .ok bindings =>
      let (built, afterBuild) := construct bindings afterRequirements
      match built with
      | .error cause => (.error cause, afterBuild)
      | .ok raw =>
        if raw.source != handle.source then (.error "scope source mismatch", afterBuild)
        else
          let (checked, afterNormalize) := normalize raw.value afterBuild
          match checked with
          | .error cause => (.error cause, afterNormalize)
          | .ok candidate => returnScope handle bindings candidate afterNormalize

/-- Metadata preparation has no resolver, normalizer or scope constructor. -/
theorem pending_preserves_requirements (metadata : Metadata) (generation revision : Nat) :
    (pending metadata generation revision).metadata.dependencies = metadata.dependencies := rfl

/-- Disabled/missing requirements reject before any construction callback. -/
theorem unavailable_before_effects (handle : Handle) (world : World)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope)
    (unavailable : ready handle world = false) :
    materialize handle resolve check construct normalize world =
      (.error "selection unavailable or stale", world) := by
  simp [materialize, unavailable]

/-- Reuse the upstream first-failure theorem: suffix callbacks cannot suppress
an earlier failure or discard the state returned by its callback. -/
theorem requirement_first_failure (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope) (world final : World)
    (dependencies : List Dependency) (cause : String) :
    Validation.traverseState (checkRequirement resolve check) world dependencies =
      (.error cause, final) ↔
    ∃ before item after values next,
      dependencies = before ++ item :: after ∧
      Validation.traverseState (checkRequirement resolve check) world before = (.ok values, next) ∧
      checkRequirement resolve check next item = (.error cause, final) :=
  Validation.traverseState_error_iff _ _ _ _ _

theorem checked_requirement_keeps_origin (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope) (world next : World)
    (dependency : Dependency) (binding : Binding)
    (success : checkRequirement resolve check world dependency = (.ok binding, next)) :
    binding.dependency = dependency := by
  unfold checkRequirement at success
  split at success
  · simp at success
  · rcases resolution : resolve dependency.target world with ⟨outcome, afterResolve⟩
    simp only [resolution] at success
    cases outcome with
    | error cause => simp at success
    | ok provider =>
      simp only at success
      split at success
      · simp at success
      · rcases normalization : check dependency provider.value afterResolve with ⟨outcome, afterCheck⟩
        simp only [normalization] at success
        cases outcome with
        | error cause => simp [Except.map] at success
        | ok candidate =>
          have same := congrArg Prod.fst success
          simp only [Except.map, Except.ok.injEq] at same
          cases same
          rfl

/-- No requirement is collapsed by target/alias or lost from the output order. -/
theorem every_requirement_retained (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope) (world final : World)
    (requirements : List Dependency) (bindings : List Binding)
    (success : Validation.traverseState (checkRequirement resolve check) world requirements =
      (.ok bindings, final)) : bindings.map Binding.dependency = requirements :=
  Validation.traverseState_project _ Binding.dependency
    (fun state item output next accepted =>
      checked_requirement_keeps_origin resolve check state next item output accepted)
    world final requirements bindings success

theorem failed_requirements_block_constructor (handle : Handle) (world final : World)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope)
    (available : ready handle world = true) (cause : String)
    (failed : Validation.traverseState (checkRequirement resolve check) world
      handle.metadata.dependencies = (.error cause, final)) :
    materialize handle resolve check construct normalize world = (.error cause, final) := by
  simp [materialize, available, failed]

theorem return_preserves_normalized_candidate (handle : Handle) (bindings : List Binding)
    (candidate : Scope) (world : World) (accepted : Admission)
    (success : (returnScope handle bindings candidate world).1 = .ok accepted) :
    accepted.candidate = candidate ∧ accepted.dependencies = bindings := by
  unfold returnScope at success
  split at success
  · cases success
    exact ⟨rfl, rfl⟩
  · contradiction

theorem changed_provider_rejected (handle : Handle) (bindings : List Binding)
    (candidate : Scope) (world : World) (binding : Binding)
    (member : binding ∈ bindings) (changed : stampCurrent world binding.source = false) :
    (returnScope handle bindings candidate world).1 = .error "stale scope sources" := by
  have notAll : bindings.all (fun item => stampCurrent world item.source) = false := by
    apply Bool.eq_false_iff.mpr
    intro allCurrent
    have checked := List.all_eq_true.mp allCurrent binding member
    simp [changed] at checked
  simp [returnScope, notAll]

/-! A callback boundary is a semantic obligation, not a cached approval. This
slice projects already known source stamps; actual MOP support completeness and
read-only source observation still have to be established from the issuer. -/
namespace Boundary

/-! Observer delivery is a second failure authority. This algebra projects
completed body/end deliveries; it does not model continuation unwinding or
claim that observer delivery is read-only. Scheme retains the actual causes
in its existing Error irritants rather than introducing a public carrier. -/
inductive ObservedFailure (Cause : Type) where
  | body (cause : Cause)
  | observer (cause : Cause)
  | both (body observer : Cause)
  deriving DecidableEq, Repr

def finishObserved (body : Except Cause Value) (observer : Except Cause Unit) :
    Except (ObservedFailure Cause) Value :=
  match body, observer with
  | .ok value, .ok () => .ok value
  | .error cause, .ok () => .error (.body cause)
  | .ok _, .error cause => .error (.observer cause)
  | .error first, .error second => .error (.both first second)

theorem observer_cannot_mask_body (first second : Cause) :
    finishObserved (.error first : Except Cause Value) (.error second) =
      .error (.both first second) := rfl

theorem successful_observer_keeps_body (cause : Cause) :
    finishObserved (.error cause : Except Cause Value) (.ok ()) =
      .error (.body cause) := rfl

theorem successful_body_keeps_observer (value : Value) (cause : Cause) :
    finishObserved (.ok value) (.error cause) = .error (.observer cause) := rfl

theorem observed_success_is_body_value (value : Value) :
    finishObserved (.ok value : Except Cause Value) (.ok ()) = .ok value := rfl

-- False-valued exceptions are data; they cannot double as a no-failure marker.
#guard match finishObserved (.error false : Except Bool Nat) (.error true) with
  | .error (.both false true) => true
  | _ => false

def current (handle : Handle) (bindings : List Binding) (world : World) : Bool :=
  ready handle world && bindings.all (fun binding => stampCurrent world binding.source)

def invoke (handle : Handle) (bindings : List Binding) (action : Action Value) : Action Value :=
  fun world =>
    if !current handle bindings world then (.error "stale before callback", world)
    else
      let (result, after) := action world
      match result with
      | .error cause => (.error cause, after)
      | .ok value =>
        if current handle bindings after then (.ok value, after)
        else (.error "stale after callback", after)

theorem stale_entry_blocks_callback (handle : Handle) (bindings : List Binding)
    (action : Action Value) (world : World)
    (stale : current handle bindings world = false) :
    invoke handle bindings action world = (.error "stale before callback", world) := by
  simp [invoke, stale]

theorem callback_failure_keeps_cause_and_state (handle : Handle) (bindings : List Binding)
    (action : Action Value) (before after : World) (cause : String)
    (fresh : current handle bindings before = true)
    (failed : action before = (.error cause, after)) :
    invoke handle bindings action before = (.error cause, after) := by
  simp [invoke, fresh, failed]

theorem successful_return_has_fresh_support (handle : Handle) (bindings : List Binding)
    (action : Action Value) (before after : World) (value : Value)
    (accepted : invoke handle bindings action before = (.ok value, after)) :
    current handle bindings before = true ∧ current handle bindings after = true := by
  unfold invoke at accepted
  split at accepted
  · simp at accepted
  · rename_i entry
    have fresh : current handle bindings before = true := by simpa using entry
    rcases outcome : action before with ⟨result, next⟩
    simp only [outcome] at accepted
    cases result with
    | error cause => simp at accepted
    | ok output =>
      simp only at accepted
      split at accepted
      · rename_i tail
        cases accepted
        exact ⟨fresh, tail⟩
      · simp at accepted

theorem changed_support_stops_success (handle : Handle) (bindings : List Binding)
    (action : Action Value) (before after : World) (value : Value)
    (fresh : current handle bindings before = true)
    (ran : action before = (.ok value, after))
    (changed : current handle bindings after = false) :
    invoke handle bindings action before = (.error "stale after callback", after) := by
  simp [invoke, fresh, ran, changed]

theorem successful_return_is_callback_result (handle : Handle) (bindings : List Binding)
    (action : Action Value) (before after : World) (value : Value)
    (accepted : invoke handle bindings action before = (.ok value, after)) :
    action before = (.ok value, after) := by
  unfold invoke at accepted
  split at accepted
  · simp at accepted
  · rcases outcome : action before with ⟨result, next⟩
    simp only [outcome] at accepted
    cases result with
    | error cause => simp at accepted
    | ok output =>
      simp only at accepted
      split at accepted
      · cases accepted
        rfl
      · simp at accepted

end Boundary

/-! Integrated reference algorithm. Keep the earlier final-only algorithm as
the comparison model; it is not a second proposed runtime entrypoint. The state
thread below retains the ordered, already checked prefix, never an admission
verdict. Every resolver, requirement, constructor and normalizer is independent.
This is a known-support model, not a proof that Scheme external effects have no
dependencies beyond the extracted source frame. -/
def checkedRequirement (handle : Handle) (prior : List Binding)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (dependency : Dependency) : Action Binding := fun world =>
  let (resolved, afterResolve) := Boundary.invoke handle prior (resolve dependency.target) world
  match resolved with
  | .error cause => (.error cause, afterResolve)
  | .ok provider =>
    if provider.source.owner != dependency.target then
      (.error "provider owner mismatch", afterResolve)
    else
      let support := prior ++ [⟨dependency, provider.source, provider.value⟩]
      let (checked, afterCheck) :=
        Boundary.invoke handle support (check dependency provider.value) afterResolve
      (checked.map (fun candidate => ⟨dependency, provider.source, candidate⟩), afterCheck)

def requirementStep (handle : Handle) (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope)
    (state : World × List Binding) (dependency : Dependency) :
    Except String Binding × (World × List Binding) :=
  let (result, after) := checkedRequirement handle state.2 resolve check dependency state.1
  (result, (after, match result with
    | .error _ => state.2
    | .ok binding => state.2 ++ [binding]))

def execute (handle : Handle) (resolve : String → Action Materialized)
    (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope) :
    Action Admission := fun world =>
  if !ready handle world then (.error "selection unavailable or stale", world)
  else
    let (requirements, afterRequirements) := Validation.traverseState
      (requirementStep handle resolve check) (world, []) handle.metadata.dependencies
    match requirements with
    | .error cause => (.error cause, afterRequirements.1)
    | .ok bindings =>
      let (built, afterBuild) :=
        Boundary.invoke handle bindings (construct bindings) afterRequirements.1
      match built with
      | .error cause => (.error cause, afterBuild)
      | .ok raw =>
        if raw.source != handle.source then (.error "scope source mismatch", afterBuild)
        else
          let (checked, afterNormalize) :=
            Boundary.invoke handle bindings (normalize raw.value) afterBuild
          match checked with
          | .error cause => (.error cause, afterNormalize)
          | .ok candidate => returnScope handle bindings candidate afterNormalize

theorem checked_requirement_keeps_dependency (handle : Handle) (prior : List Binding)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (dependency : Dependency) (before after : World) (binding : Binding)
    (accepted : checkedRequirement handle prior resolve check dependency before =
      (.ok binding, after)) : binding.dependency = dependency := by
  unfold checkedRequirement at accepted
  rcases resolution : Boundary.invoke handle prior (resolve dependency.target) before with
    ⟨result, afterResolve⟩
  simp only [resolution] at accepted
  cases result with
  | error cause => simp at accepted
  | ok provider =>
    simp only at accepted
    split at accepted
    · simp at accepted
    · rcases checking : Boundary.invoke handle
        (prior ++ [⟨dependency, provider.source, provider.value⟩])
        (check dependency provider.value) afterResolve with ⟨outcome, afterCheck⟩
      simp only [checking] at accepted
      cases outcome with
      | error cause => simp [Except.map] at accepted
      | ok candidate =>
        have same := congrArg Prod.fst accepted
        simp only [Except.map, Except.ok.injEq] at same
        cases same
        rfl

theorem requirement_step_keeps_dependency (handle : Handle)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (before after : World × List Binding) (dependency : Dependency) (binding : Binding)
    (accepted : requirementStep handle resolve check before dependency = (.ok binding, after)) :
    binding.dependency = dependency := by
  unfold requirementStep at accepted
  rcases checking : checkedRequirement handle before.2 resolve check dependency before.1 with
    ⟨result, next⟩
  simp only [checking] at accepted
  cases result with
  | error cause => simp at accepted
  | ok value =>
    cases accepted
    exact checked_requirement_keeps_dependency handle before.2 resolve check dependency
      before.1 next binding checking

theorem execution_keeps_every_requirement (handle : Handle)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (before after : World × List Binding) (bindings : List Binding)
    (accepted : Validation.traverseState (requirementStep handle resolve check)
      before handle.metadata.dependencies = (.ok bindings, after)) :
    bindings.map Binding.dependency = handle.metadata.dependencies :=
  Validation.traverseState_project _ Binding.dependency
    (fun state dependency binding next success =>
      requirement_step_keeps_dependency handle resolve check state next dependency binding success)
    before after handle.metadata.dependencies bindings accepted

theorem execution_requirement_failure_blocks_construction (handle : Handle)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope)
    (before : World) (after : World × List Binding) (cause : String)
    (fresh : ready handle before = true)
    (failed : Validation.traverseState (requirementStep handle resolve check)
      (before, []) handle.metadata.dependencies = (.error cause, after)) :
    execute handle resolve check construct normalize before = (.error cause, after.1) := by
  simp [execute, fresh, failed]

/-- The integrated successful result retains the complete ordered requirements
and authenticates the original source frame at its actual return state. -/
theorem execution_success_is_complete_and_current (handle : Handle)
    (resolve : String → Action Materialized) (check : Dependency → Scope → Action Scope)
    (construct : List Binding → Action Materialized) (normalize : Scope → Action Scope)
    (before after : World) (admitted : Admission)
    (accepted : execute handle resolve check construct normalize before = (.ok admitted, after)) :
    admitted.dependencies.map Binding.dependency = handle.metadata.dependencies ∧
      Boundary.current handle admitted.dependencies after = true := by
  unfold execute at accepted
  split at accepted
  · simp at accepted
  · rcases requirements : Validation.traverseState (requirementStep handle resolve check)
        (before, []) handle.metadata.dependencies with ⟨result, afterRequirements⟩
    simp only [requirements] at accepted
    cases result with
    | error cause => simp at accepted
    | ok bindings =>
      simp only at accepted
      rcases construction : Boundary.invoke handle bindings (construct bindings)
          afterRequirements.1 with ⟨result, afterBuild⟩
      simp only [construction] at accepted
      cases result with
      | error cause => simp at accepted
      | ok raw =>
        simp only at accepted
        split at accepted
        · simp at accepted
        · rcases normalization : Boundary.invoke handle bindings (normalize raw.value)
              afterBuild with ⟨result, afterNormalize⟩
          simp only [normalization] at accepted
          cases result with
          | error cause => simp at accepted
          | ok candidate =>
            simp only at accepted
            have projection := return_preserves_normalized_candidate handle bindings candidate
              afterNormalize admitted (congrArg Prod.fst accepted)
            have complete := execution_keeps_every_requirement handle resolve check
              (before, []) afterRequirements bindings requirements
            unfold returnScope at accepted
            split at accepted
            · rename_i fresh
              cases accepted
              exact ⟨complete, fresh⟩
            · simp at accepted

namespace Counterexamples
def database : Dependency := ⟨"database", "postgresql"⟩
def policy : Dependency := ⟨"policy", "postgresql"⟩
def metadata : Metadata := ⟨"application", [database, policy], []⟩
def handle : Handle := pending metadata 7 3
def world : World := ⟨7, ["application", "postgresql"], [],
  [("application", 3), ("postgresql", 9)]⟩
def provider (_owner : String) : Action Materialized :=
  fun state => (.ok ⟨⟨"postgresql", 9⟩, ⟨17, 5432⟩⟩, state)
def portCheck (dependency : Dependency) (candidate : Scope) : Action Scope :=
  fun state =>
    if dependency.alias == "policy" && candidate.port != 5440 then
      (.error "policy port mismatch", state)
    else (.ok candidate, state)
def construct (_bindings : List Binding) : Action Materialized :=
  fun state => (.ok ⟨⟨"application", 3⟩, ⟨40, 5432⟩⟩, state)
def normalize (candidate : Scope) : Action Scope :=
  fun state => (.ok {candidate with receiver := candidate.receiver + 1}, state)
def databaseOnly : Handle :=
  {handle with metadata := {metadata with dependencies := [database]}}

-- This represents the UNSOUND algorithm that keeps only read aliases. The
-- conflicting second requirement has vanished although the source is unchanged.
#guard match (materialize handle provider portCheck construct normalize world).1 with
  | .error cause => cause == "policy port mismatch"
  | .ok _ => false
#guard match (materialize databaseOnly provider portCheck construct normalize world).1 with
  | .ok accepted => accepted.candidate.receiver == 41
  | .error _ => false
#guard match (materialize handle provider portCheck
  (fun _ state => (.error "constructor must not run", state)) normalize world).1 with
  | .error cause => cause == "policy port mismatch"
  | .ok _ => false

-- Normalization cannot update the original provider stamp to hide a source edit.
def changedSource (candidate : Scope) : Action Scope :=
  fun state => (.ok candidate,
    {state with sources := [("application", 3), ("postgresql", 10)]})
#guard match (materialize databaseOnly provider portCheck construct changedSource world).1 with
  | .error cause => cause == "stale scope sources"
  | .ok _ => false
#guard match (materialize databaseOnly provider portCheck construct normalize
  {world with generation := 8}).1 with
  | .error cause => cause == "selection unavailable or stale"
  | .ok _ => false

-- A final-only guard can miss a change followed by a later callback restoring
-- the observed endpoint. This does not model a monotone MOP revision as mutable:
-- World.sources are external observations, where endpoint-only ABA is possible.
def changeDuringBuild (_bindings : List Binding) : Action Materialized :=
  fun state => (.ok ⟨⟨"application", 3⟩, ⟨40, 5432⟩⟩,
    {state with sources := [("application", 3), ("postgresql", 10)]})
def restoreDuringNormalize (candidate : Scope) : Action Scope :=
  fun state => (.ok candidate, {state with sources := world.sources})
def checkedDatabase : Binding := ⟨database, ⟨"postgresql", 9⟩, ⟨17, 5432⟩⟩

#guard match (materialize databaseOnly provider portCheck changeDuringBuild
    restoreDuringNormalize world).1 with
  | .ok _ => true
  | .error _ => false
#guard match (Boundary.invoke databaseOnly [checkedDatabase]
    (changeDuringBuild [checkedDatabase]) world).1 with
  | .error cause => cause == "stale after callback"
  | .ok _ => false

-- Preserve an earlier callback's own refusal, even when it also changes source.
#guard match (Boundary.invoke databaseOnly [checkedDatabase]
    (fun state => (.error "domain port conflict",
      {state with sources := [("application", 3), ("postgresql", 10)]}) : Action Scope)
    world).1 with
  | .error cause => cause == "domain port conflict"
  | .ok _ => false

-- End-to-end reference controls: resolve, both requirements, construct from
-- actual checked bindings, normalize, and perform independent return checks.
def finalPortPlan (bindings : List Binding) : Action Materialized := fun state =>
  match bindings with
  | [] => (.error "missing database binding", state)
  | databaseBinding :: _ =>
    (.ok ⟨⟨"application", 3⟩, ⟨40, databaseBinding.candidate.port⟩⟩, state)
def provider5440 (_owner : String) : Action Materialized :=
  fun state => (.ok ⟨⟨"postgresql", 9⟩, ⟨18, 5440⟩⟩, state)
def portContract (_dependency : Dependency) (candidate : Scope) : Action Scope :=
  fun state =>
    if 0 < candidate.port && candidate.port ≤ 65535 then (.ok candidate, state)
    else (.error "port outside 1..65535", state)

#guard match (execute handle provider portCheck finalPortPlan normalize world).1 with
  | .error cause => cause == "policy port mismatch"
  | .ok _ => false
#guard match (execute handle provider5440 portCheck finalPortPlan normalize world).1 with
  | .ok admitted => admitted.candidate.port == 5440 &&
      admitted.dependencies.map Binding.dependency == [database, policy]
  | .error _ => false
#guard match (execute databaseOnly provider portContract finalPortPlan normalize world).1,
    (execute databaseOnly provider5440 portContract finalPortPlan normalize world).1 with
  | .ok parent, .ok child => parent.candidate.port == 5432 && child.candidate.port == 5440
  | _, _ => false
#guard match (execute databaseOnly provider portContract changeDuringBuild
    restoreDuringNormalize world).1 with
  | .error cause => cause == "stale after callback"
  | .ok _ => false
-- A hot value is not an approval: a new execution with changed source fails
-- even though the resolver would return the same old port and source stamp.
#guard match (execute databaseOnly provider portContract finalPortPlan normalize
    {world with sources := [("application", 3), ("postgresql", 10)]}).1 with
  | .error cause => cause == "stale before callback"
  | .ok _ => false
end Counterexamples

end YuanxuProof.ModuleSystem.Loading.ManagedBinding
