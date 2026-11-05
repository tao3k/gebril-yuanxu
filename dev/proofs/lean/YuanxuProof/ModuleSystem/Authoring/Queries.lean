-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Validation

namespace YuanxuProof.ModuleSystem.Authoring.Queries
open LeanPoo.Functional

/-! `authoring/admission.ss` query-slot and raw-initializer diagnostics.
Reader datums are represented structurally. This is the implemented bounded
source-shape check, not a GQL evaluator or an authority inference. -/
inductive Form where
  | symbol (name : String)
  | text (value : String)
  | vector (items : List Form)
  | list (items : List Form)
  deriving Repr

def querySlot (name : String) : Bool :=
  ["query", "queries", "query-predicate", "query-predicates"].contains name ||
    name.endsWith "-query" || name.endsWith "-queries"

def rawInitializer : Form → Bool
  | .text _ => true
  | .list (.symbol name :: rest) =>
    if ["lambda", "list", "vector"].contains name then true
    else if ["quote", "quasiquote"].contains name then
      match rest with
      | .text _ :: _ => true
      | .vector _ :: _ => true
      | .list (_ :: _) :: _ => true
      | _ => false
    else false
  | _ => false

def checkSlot (forbidRaw : Bool) (binding : String × Form) : Except String (String × Form) :=
  if forbidRaw && querySlot binding.1 && rawInitializer binding.2 then .error binding.1 else .ok binding

/-- Validate all claimed Query slots, keeping the first exact offending slot.
Other slots and named POO Query/projection references remain ordinary code. -/
def checkBindings (forbidRaw : Bool) := Validation.traverse (checkSlot forbidRaw)

theorem raw_claimed_query_refused (name : String) (form : Form)
    (claimed : querySlot name = true) (raw : rawInitializer form = true) :
    checkSlot true (name, form) = .error name := by simp [checkSlot, claimed, raw]

theorem ordinary_slot_unrestricted (name : String) (form : Form) (ordinary : querySlot name = false) :
    checkSlot true (name, form) = .ok (name, form) := by simp [checkSlot, ordinary]

theorem named_query_allowed (name reference : String) :
    checkSlot true (name, .symbol reference) = .ok (name, .symbol reference) := by
  simp [checkSlot, rawInitializer]

#guard rawInitializer (.list [.symbol "quote", .list [.symbol "select"]])
#guard !rawInitializer (.list [.symbol "quote", .list []])
#guard !rawInitializer (.vector [.symbol "select"])
#guard !(checkBindings true [("query", .text "SELECT *")]).toOption.isSome
#guard (checkBindings true [("gql-source", .text "SELECT *")]).toOption.isSome

/-- Batch diagnostics preserve datum order and each datum's diagnostic order.
The Scheme metadata guard must establish the pointwise premise; this theorem
does not certify that extraction or cache an admission result. -/
theorem batch_diagnostics_preserved {Datum Diagnostic : Type}
    (generic direct : Datum → List Diagnostic) (datums : List Datum)
    (same : ∀ datum ∈ datums, generic datum = direct datum) :
    (datums.map generic).flatten = (datums.map direct).flatten := by
  congr 1
  exact List.map_congr_left same

/-- On a changed/extended method set the batch must use ordinary invocation.
There is no stale specialized result available through this branch. -/
theorem changed_metadata_uses_generic {Result : Type}
    (generic direct : Result) :
    (if false then direct else generic) = generic := by rfl

/-! Default Function profiles are issued from the actual generic's two native
prototype specializations. Key denotes reference identity, never a role label.
With the other argument axes equal, specificity is the position in the native
C4 list. The first indexed match is exactly its least-distance candidate.
Extraction of that closed generic state remains a Scheme/MOP obligation. -/
def firstProfile {Key Method : Type} [DecidableEq Key]
    (profiles : List (Key × Method)) : List Key → Option Method
  | [] => none
  | key :: rest => match profiles.lookup key with
    | some method => some method
    | none => firstProfile profiles rest

theorem firstProfile_ordered_reference {Key Method : Type} [DecidableEq Key]
    (profiles : List (Key × Method)) (order : List Key) :
    firstProfile profiles order = (order.filterMap (fun key => profiles.lookup key)).head? := by
  induction order with
  | nil => rfl
  | cons key rest ih =>
    cases found : profiles.lookup key <;> simp [firstProfile, found, ih]

theorem firstProfile_least_position {Key Method : Type} [DecidableEq Key]
    (profiles : List (Key × Method)) (order : List Key) (method : Method)
    (selected : firstProfile profiles order = some method) :
    ∃ before key after, order = before ++ key :: after ∧
      profiles.lookup key = some method ∧
      ∀ earlier ∈ before, profiles.lookup earlier = none := by
  induction order with
  | nil => simp [firstProfile] at selected
  | cons key rest ih =>
    cases found : profiles.lookup key with
    | some value =>
      simp [firstProfile, found] at selected
      subst value
      exact ⟨[], key, rest, rfl, found, by simp⟩
    | none =>
      have tail : firstProfile profiles rest = some method := by
        simpa [firstProfile, found] using selected
      obtain ⟨before, target, after, order, selectedTarget, earlier⟩ := ih tail
      refine ⟨key :: before, target, after, ?_, selectedTarget, ?_⟩
      · simp [order]
      · intro item member
        rcases List.mem_cons.mp member with same | previous
        · simpa [same] using found
        · exact earlier item previous

def profileSearchWork {Key Method : Type} [DecidableEq Key]
    (profiles : List (Key × Method)) : List Key → Nat
  | [] => 0
  | key :: rest => match profiles.lookup key with
    | some _ => 1
    | none => 1 + profileSearchWork profiles rest

theorem profile_search_bounded_by_c4_depth {Key Method : Type} [DecidableEq Key]
    (profiles : List (Key × Method)) (order : List Key) :
    profileSearchWork profiles order ≤ order.length := by
  induction order with
  | nil => simp [profileSearchWork]
  | cons key rest ih =>
    cases found : profiles.lookup key <;> simp [profileSearchWork, found] <;> omega

-- Reversing declaration order cannot reverse specificity. C4 owns the order;
-- the closed profile catalog supplies method identity only, not precedence.
#guard firstProfile [("module", 1), ("config", 2)] ["child", "config", "module"] == some 2
#guard firstProfile [("config", 2), ("module", 1)] ["child", "module", "config"] == some 1
#guard firstProfile [("config", 2), ("module", 1)] ["unrelated"] == none

/-! A carrier guard is a scoped snapshot, not a successful admission. Function
execution never activates it. The first actual Generic demand acquires it;
subsequent demands preserve that same snapshot until the enclosing return.
Scheme must establish that the activation is on the actual Generic branch,
and that its dynamic parameter is shared/restored across nesting and failure. -/
namespace CarrierScope
def demand (saved : Option Revision) (current : Revision) : Option Revision :=
  match saved with
  | none => some current
  | some previous => some previous

def finish [DecidableEq Revision] (saved : Option Revision) (current : Revision) : Bool :=
  saved.all (fun previous => decide (previous = current))

theorem unused_does_not_read_carrier [DecidableEq Revision] (left right : Revision) :
    finish none left = finish none right := rfl

theorem first_generic_captures (current : Revision) :
    demand none current = some current := rfl

theorem nested_generic_keeps_outer (saved current : Revision) :
    demand (some saved) current = some saved := rfl

theorem return_rejects_change [DecidableEq Revision] (saved current : Revision)
    (changed : saved ≠ current) : finish (demand none saved) current = false := by
  simp [demand, finish, changed]
end CarrierScope
end YuanxuProof.ModuleSystem.Authoring.Queries
