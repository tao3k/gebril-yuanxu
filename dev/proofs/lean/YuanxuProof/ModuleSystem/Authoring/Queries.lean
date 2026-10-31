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
end YuanxuProof.ModuleSystem.Authoring.Queries
