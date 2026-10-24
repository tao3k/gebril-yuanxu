-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation
import LeanPoo.Object.MultimethodSemantics

namespace YuanxuProof.PooClos.MethodCombination
open LeanPoo.Functional

/-! Pure qualifier matching and ordered combination from
`poo-clos/method-combination.ss`. Predicate matchers and native side effects are
outside this declarative-pattern fragment; they are not assumed to succeed. -/
inductive Pattern where
  | rest
  | end
  | cons (head : Option String) (tail : Pattern)
  deriving Repr, DecidableEq

def patternMatches : Pattern → List String → Bool
  | .rest, _ => true
  | .end, values => values.isEmpty
  | .cons _ _, [] => false
  | .cons head tail, value :: values =>
      (match head with | none => true | some expected => expected == value) && patternMatches tail values

theorem exact_length (pattern : List String) (values : List String) :
    patternMatches (pattern.foldr (fun name tail => .cons (some name) tail) .end) values = true ↔
      pattern = values := by
  induction pattern generalizing values with
  | nil => cases values <;> simp [patternMatches]
  | cons head tail ih => cases values <;> simp [patternMatches, ih]

structure Group where
  reference : Nat
  patterns : List Pattern
  required : Bool
  mostSpecificLast : Bool
  deriving Repr, DecidableEq

/-- Native `find` assigns each method only to its first matching group.
`reference` projects group object identity (`eq?`), not its possibly repeated label. -/
def firstGroup (groups : List Group) (qualifiers : List String) : Option Group :=
  groups.find? (fun group => group.patterns.any (fun pattern => patternMatches pattern qualifiers))

theorem first_match_wins (head : Group) (tail : List Group) (qualifiers : List String)
    (matched : head.patterns.any (fun pattern => patternMatches pattern qualifiers) = true) :
    firstGroup (head :: tail) qualifiers = some head := by simp [firstGroup, matched]

/-- Methods are retained as factories; eager combinations use the library's
ordered sequence/fold rather than a second invocation or composition engine. -/
def eagerList {Context Value : Type} (methods : List (Factory Context (fun _ => Value))) :=
  Factory.sequence methods

def progn {Context Value : Type} (methods : List (Factory Context (fun _ => Option Value))) :=
  Factory.fold (fun _ _ result => result) (fun _ => none) methods

theorem eager_order {Context Value : Type} (left right : List (Factory Context (fun _ => Value)))
    (context : Context) :
    eagerList (left ++ right) context = eagerList left context ++ eagerList right context :=
  Factory.sequence_append left right context

theorem progn_last {Context Value : Type} (methods : List (Factory Context (fun _ => Option Value)))
    (last : Factory Context (fun _ => Option Value)) (context : Context) :
    progn (methods ++ [last]) context = last context := by
  simp [progn, Factory.fold, List.foldl_append]

inductive Qualifier where
  | symbol (name : String)
  | explicit (names : List String)
  deriving Repr, DecidableEq

/-- Preserve the original qualifier for ambiguity checks, even when primary
and an explicit empty list normalize to the same long-form pattern input. -/
def Qualifier.names : Qualifier → List String
  | .symbol name => if name == "primary" then [] else [name]
  | .explicit names => names

structure RankedMethod where
  identity : Nat
  qualifier : Qualifier
  rank : List Nat
  deriving Repr, DecidableEq

def ambiguous : List RankedMethod → Bool
  | first :: second :: rest =>
      (first.rank == second.rank && first.qualifier != second.qualifier) || ambiguous (second :: rest)
  | _ => false

inductive GroupFailure where
  | ambiguousOrder | requiredEmpty | invalidQualifier
  deriving Repr, DecidableEq

/-- Assignment preserves the global specificity order; only the declared
most-specific-last group reverses it. Ambiguity is checked before emptiness. -/
def groupMethods (groups : List Group) (ranked : List RankedMethod) (group : Group) :=
  let assigned := ranked.filter (fun method =>
    (firstGroup groups method.qualifier.names).map Group.reference == some group.reference)
  if group.mostSpecificLast then assigned.reverse else assigned

def checkGroup (group : Group) (methods : List RankedMethod) : Except GroupFailure (List RankedMethod) :=
  if ambiguous methods then .error .ambiguousOrder
  else if group.required && methods.isEmpty then .error .requiredEmpty
  else .ok methods

def assignMethod (groups : List Group) (method : RankedMethod) : Except GroupFailure Nat :=
  match firstGroup groups method.qualifier.names with
  | none => .error .invalidQualifier
  | some group => .ok group.reference

def partition (groups : List Group) (ranked : List RankedMethod) :=
  (Validation.traverse (assignMethod groups) ranked).bind fun _ =>
    Validation.traverse (fun group => checkGroup group (groupMethods groups ranked group)) groups

theorem unmatched_first_rejected (groups : List Group) (head : RankedMethod) (tail : List RankedMethod)
    (unmatched : firstGroup groups head.qualifier.names = none) :
    partition groups (head :: tail) = .error .invalidQualifier := by
  simp [partition, Validation.traverse, assignMethod, unmatched, Except.bind]


theorem accepted_group_valid (group : Group) (methods output : List RankedMethod)
    (accepted : checkGroup group methods = .ok output) :
    ambiguous methods = false ∧ (group.required = true → methods ≠ []) ∧ output = methods := by
  unfold checkGroup at accepted
  split at accepted
  · contradiction
  · rename_i unambiguous
    split at accepted
    · contradiction
    · rename_i nonempty
      refine ⟨Bool.eq_false_iff.mpr unambiguous, ?_, (Except.ok.inj accepted).symm⟩
      intro required empty
      subst methods
      simp [required] at nonempty

/-- Applicability uses LeanPoo's method selection at every call, including a
warm candidate sequence. A value predicate cannot be cached as applicability. -/
def applicable {Args : Type} (candidates : Array (LeanPoo.Object.MethodCandidate Args RankedMethod))
    (args : Args) : List RankedMethod :=
  (LeanPoo.Object.MethodCandidate.select candidates args).toList

theorem applicable_reference {Args : Type}
    (candidates : Array (LeanPoo.Object.MethodCandidate Args RankedMethod)) (args : Args) :
    applicable candidates args = candidates.toList.filterMap
      (LeanPoo.Object.MethodCandidate.selected args) :=
  LeanPoo.Object.MethodCandidate.select_reference candidates args

/-- Boolean-result fragment of the native and/or control drivers. Factories
in the unused suffix are not applied. Other Scheme truthy values need the
native value representation and are outside this fragment. -/
def shortAnd {Context : Type} : List (Factory Context (fun _ => Bool)) → Factory Context (fun _ => Bool)
  | [] => fun _ => true
  | head :: tail => Factory.bind head (fun _ value =>
      Factory.choose (fun _ => value) (shortAnd tail) (fun _ => false))

def shortOr {Context : Type} : List (Factory Context (fun _ => Bool)) → Factory Context (fun _ => Bool)
  | [] => fun _ => false
  | head :: tail => Factory.bind head (fun _ value =>
      Factory.choose (fun _ => value) (fun _ => true) (shortOr tail))

theorem and_false_skips_suffix {Context : Type} (head : Factory Context (fun _ => Bool))
    (tail : List (Factory Context (fun _ => Bool))) (context : Context) (stop : head context = false) :
    shortAnd (head :: tail) context = false := by
  simp [shortAnd, Factory.bind, Factory.choose, stop]

theorem or_true_skips_suffix {Context : Type} (head : Factory Context (fun _ => Bool))
    (tail : List (Factory Context (fun _ => Bool))) (context : Context) (stop : head context = true) :
    shortOr (head :: tail) context = true := by
  simp [shortOr, Factory.bind, Factory.choose, stop]

#guard ambiguous [⟨1, .symbol "primary", [0]⟩, ⟨2, .explicit [], [0]⟩]
#guard match checkGroup ⟨1, [.rest], true, false⟩ [] with
  | .error .requiredEmpty => true | _ => false
#guard match checkGroup ⟨1, [.rest], false, false⟩ [⟨1, .symbol "a", [0]⟩, ⟨2, .symbol "b", [0]⟩] with
  | .error .ambiguousOrder => true | _ => false
#guard (applicable #[.when (fun (arg : Nat) => arg == 1) ⟨1, .symbol "primary", []⟩] 2).isEmpty
#guard patternMatches (.cons none .end) ["before"]
#guard !patternMatches (.cons none .end) ["before", "extra"]
#guard patternMatches (.cons (some "around") .rest) ["around", "extra"]
#guard firstGroup [⟨1, [.rest], false, false⟩, ⟨2, [.rest], true, false⟩] ["before"] ==
  some ⟨1, [.rest], false, false⟩
#guard eagerList [fun (_ : Unit) => 2, fun _ => 1] () == [2, 1]
#guard progn [fun (_ : Unit) => some 2, fun _ => some 1] () == some 1
end YuanxuProof.PooClos.MethodCombination
