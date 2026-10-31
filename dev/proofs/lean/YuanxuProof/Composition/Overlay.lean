-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Assembly

namespace YuanxuProof.Composition.Overlay
open LeanPoo.Functional
/-! `composition/roles.ss` constant-slot fast path. Each role's existing
constant slots are projected as a provider. Dynamic/self/super slots continue
through native .mix; this finite lookup law is not applied to them. -/
def overlay (roles : List (Provider Context Key Value)) : Provider Context Key Value :=
  roles.foldr Provider.compose (fun _ => none)

def reference (roles : List (Provider Context Key Value)) (key : Key) : Option (Factory Context (fun c => Value c key)) :=
  match roles with
  | [] => none
  | head :: rest => match head key with | some value => some value | none => reference rest key

theorem indexed_overlay_matches_first_owner (roles : List (Provider Context Key Value)) (key : Key) :
    overlay roles key = reference roles key := by
  induction roles with
  | nil => rfl
  | cons head rest ih =>
    simp only [overlay, List.foldr_cons, Provider.compose, reference]
    cases head key <;> simp_all [overlay]

theorem first_owner_wins (head : Provider Context Key Value) (rest : List (Provider Context Key Value))
    (key : Key) (factory : Factory Context (fun c => Value c key)) (provided : head key = some factory) :
    overlay (head :: rest) key = some factory := by simp [overlay, Provider.compose, provided]

#guard (overlay [fun name => if name == "x" then some (fun (_ : Unit) => 1) else none,
    fun _ => some (fun _ => 2)] "x").map (fun factory => factory ()) == some 1
#guard (overlay [fun name => if name == "x" then some (fun (_ : Unit) => 1) else none,
    fun _ => some (fun _ => 2)] "fallback").map (fun factory => factory ()) == some 2
end YuanxuProof.Composition.Overlay
