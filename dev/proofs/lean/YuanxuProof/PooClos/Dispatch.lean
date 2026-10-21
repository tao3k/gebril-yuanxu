-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Object.MultimethodSemantics
import YuanxuProof.PooClos.MethodCombination

namespace YuanxuProof.PooClos.Dispatch
open LeanPoo.Object

/-! `poo-clos/dispatch.ss`: the generic owns shape-indexed candidates, while
value-sensitive applicability is recomputed at each invocation. This uses
LeanPoo's real sparse index, cache, registration and call operations. Native
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
