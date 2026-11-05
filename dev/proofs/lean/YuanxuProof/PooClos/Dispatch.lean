-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Object.MultimethodSemantics
import YuanxuProof.PooClos.MethodCombination
import LeanPoo.Object.MethodCombination

namespace YuanxuProof.PooClos.Dispatch
open LeanPoo.Object

/-- A known primary which never calls next has the same monadic effects and
result without a lexical invocation carrier. This does NOT authorize eliding
public construction hooks or observers; the runtime gate must exclude them. -/
theorem closed_primary_is_function {Args Result : Type} {M : Type → Type}
    [Monad M] [LawfulMonad M] (body : Args → M Result)
    (rest : List (MethodCombination.SubMethod Args M Result))
    (missing : Args → M Result) (args : Args) :
    MethodCombination.effective
      ({ primary := (fun _ args => body args) :: rest } : MethodCombination.Methods Args M Result)
      missing args = body args := by
  simp [MethodCombination.effective, MethodCombination.callChain, MethodCombination.runSides]

/-- Per-invocation validation is outside method preparation: a prepared body
cannot turn a rejected next datum into the previous successful result. -/
def checkedFunction {Error Args Result : Type}
    (check : Args → Except Error Args) (body : Args → Except Error Result)
    (args : Args) : Except Error Result := (check args).bind body

theorem rejected_datum_is_not_reused {Error Args Result : Type}
    (check : Args → Except Error Args) (body : Args → Except Error Result)
    (args : Args) (error : Error) (rejected : check args = .error error) :
    checkedFunction check body args = .error error := by
  simp [checkedFunction, rejected, Except.bind]

/-- The scope is the actual runtime observer/precheck projection, not a purity
label on a Profile. An unknown callback cannot qualify for the function path. -/
def observationCompatible (actual allowed : List Nat) : Bool :=
  actual.all (fun callback => allowed.contains callback)

theorem unknown_observer_requires_generic (actual allowed : List Nat) (callback : Nat)
    (present : callback ∈ actual) (unknown : callback ∉ allowed) :
    observationCompatible actual allowed = false := by
  apply Bool.eq_false_iff.mpr
  intro compatible
  have members := List.all_eq_true.mp compatible
  exact unknown (List.contains_iff_mem.mp (members callback present))

/-- The maintained source precheck has no boundary callback for a hook-free
carrier. All actual domain reads still run the same precheck. -/
def sourcePrecheck (protocol : Option Nat) (boundaries : List Nat) : List Nat :=
  if protocol.isSome then boundaries else []

theorem hook_free_carrier_has_no_source_callback (boundaries : List Nat) :
    sourcePrecheck none boundaries = [] := rfl

/-- Runtime observation suppression, not a remembered Core flag, determines
which enclosing boundaries are active when entering another Reader. -/
def enterSourceScope (runtimeActive : Bool) (outer : List Nat) (inner : Nat) : List Nat :=
  inner :: (if runtimeActive then outer else [])

theorem nested_source_order (outer : List Nat) (inner : Nat) :
    enterSourceScope true outer inner = inner :: outer := rfl

theorem disabled_outer_is_not_resurrected (outer : List Nat) (inner : Nat) :
    enterSourceScope false outer inner = [inner] := rfl

/-! `poo-clos/dispatch.ss`: the generic owns shape-indexed candidates, while
value-sensitive applicability is recomputed at each invocation. This uses
LeanPoo's real sparse index, cache, registration and call operations. Runtime
class/eql precedence projection remains the adapter input; no evaluator callback
or digest/injectivity witness substitutes for method selection. -/

def selectedMethods (generic : Multimethod Args Method Result) (args : Args) : List Method :=
  (MethodCandidate.select (generic.candidatesFor (generic.precedence args)) args).toList

theorem selected_methods_reference (generic : Multimethod Args Method Result) (args : Args) :
    selectedMethods generic args =
      (generic.index.reference ((generic.precedence args).map fun order =>
        order.map Specializer.prototype ++ [.any])).filterMap (MethodCandidate.selected args) := by
  rw [selectedMethods, MethodCandidate.select_reference, generic.candidates_reference]

theorem cache_refines_reference (generic : Multimethod Args Method Result)
    (sound : generic.CacheSound) (args : Args) :
    (generic.call args).map Prod.fst = generic.referenceCall args := generic.call_correct sound args

/-- Registration establishes soundness by clearing old candidates, rather than
assuming that a generation counter makes old entries trustworthy. -/
theorem registration_establishes_sound_cache (generic updated : Multimethod Args Method Result)
    (path : List Specializer) (method : Method) (arity : path.length = generic.arity)
    (registered : generic.register path method = .ok updated) : updated.CacheSound :=
  generic.register_sound updated path method arity registered

def exampleGeneric : Multimethod Nat Nat (List Nat) where
  arity := 1
  precedence := fun _ => [["dog", "animal"]]
  combine := fun methods _ => methods.toList
  index := ((MethodIndex.empty.prepend [.prototype "animal"] (.always 2)).prepend
    [.prototype "dog"] (.when (fun value => value == 1) 1))

-- Same shape, different arguments: a warm candidate cache must not freeze the
-- earlier value predicate. Old immutable generics remain usable after edits.
#guard (exampleGeneric.call 1).toOption.map (·.1) == some [1, 2]
#guard (exampleGeneric.call 1).toOption.bind (fun pair => (pair.2.call 2).toOption.map (·.1)) == some [2]
#guard (exampleGeneric.register [.prototype "dog"] 3).toOption.bind
  (fun updated => (updated.call 2).toOption.map (·.1)) == some [3, 2]
#guard (exampleGeneric.call 2).toOption.map (·.1) == some [2]
end YuanxuProof.PooClos.Dispatch
