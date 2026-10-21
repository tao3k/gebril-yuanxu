-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.IssuedRootForwarding
import YuanxuProof.Admission.DFSFrames
import LeanPoo.Functional.ConstructionCache
import LeanPoo.Functional.ContractConsequence

namespace YuanxuProof.Admission.ReadRetention
open IssuedRootForwarding

def quintSourceDigest : String :=
  "sha256:4243cdbfc443b7ccf707180e4215d45d9b51a66396016c07c77c78428da04c09"

-- Nat denotes registry record identity, NOT receiver identity or field spelling.
def retain (visited : List Nat) : List Nat := visited.eraseDups

theorem exact_retention (visited : List Nat) (token : Nat) :
    token ∈ retain visited ↔ token ∈ visited := by simp [retain]

theorem shared_record_once (vertices roots : List Nat) (deps : IdentityDFS.Edges) :
    (DFSFrames.replay vertices deps roots).order.Nodup := DFSFrames.replay_nodup

theorem finite_cycle_drains (vertices roots : List Nat) (deps : IdentityDFS.Edges)
    (closed : IdentityDFS.Closed vertices deps)
    (within : ∀ token ∈ roots, token ∈ vertices) :
    (DFSFrames.replay vertices deps roots).frames = [] :=
  DFSFrames.replay_drains closed within

theorem preserves_every_check (visited : List Nat) (check : Nat → Prop) :
    (∀ token ∈ retain visited, check token) ↔ (∀ token ∈ visited, check token) := by
  simp [retain]

-- Apply to a COMPLETE demanded traversal, including misses/preparation/bootstrap.
-- Completeness is an explicit native-extraction premise, not a theorem about GC.
theorem closure_coverage (roots : List Nat) (deps : Nat → List Nat)
    (visited : List Nat) (complete : ∀ token, Reach roots deps token → token ∈ visited) :
    ∀ token, Reach roots deps token → token ∈ retain visited := by
  intro token demanded
  exact (exact_retention visited token).mpr (complete token demanded)

theorem omitted_dependency_refused (roots : List Nat) (deps : Nat → List Nat)
    (kept : List Nat) (token : Nat) (needed : Reach roots deps token)
    (omitted : token ∉ kept) :
    ¬ (∀ item, Reach roots deps item → item ∈ kept) := by
  intro complete
  exact omitted (complete token needed)

-- Equal receivers cannot justify dropping distinct issued records.
theorem receiver_equality_not_record_equality :
    (fun (_ : Nat) => 7) 1 = (fun (_ : Nat) => 7) 2 ∧
    ¬ (∀ token ∈ ([1, 2] : List Nat), token ∈ ([1] : List Nat)) := by decide

-- Reuse LeanPoo's exact immutable declaration and exact context guarantees.
theorem same_declaration_shares_closed {Key : Type} {Value : Key → Type}
    [DecidableEq Key] {spec : LeanPoo.Functional.GeneralizedGraph.Declaration Key Value}
    (cache : LeanPoo.Functional.ConstructionCache.Cache spec) (order : List Key) :
    (cache.retain order).closed = cache.closed :=
  LeanPoo.Functional.ConstructionCache.Cache.retain_closed cache order

theorem child_context_keeps_joint_claim
    {Value : Nat → Nat → Type} {keys : List Nat}
    {Claim : ∀ c, LeanPoo.Functional.Requirements.Results Value c keys → Prop}
    {ready : LeanPoo.Functional.Requirements.Certified keys Claim}
    (slot : LeanPoo.Functional.Requirements.ContextSlot ready) (child : Nat) :
    Claim child (slot.read child).1.val := (slot.read child).1.property.2

theorem changed_child_context_misses
    {Value : Nat → Nat → Type} {keys : List Nat}
    {Claim : ∀ c, LeanPoo.Functional.Requirements.Results Value c keys → Prop}
    {ready : LeanPoo.Functional.Requirements.Certified keys Claim}
    (slot : LeanPoo.Functional.Requirements.ContextSlot ready) (parent child : Nat)
    (data : LeanPoo.Functional.Requirements.Snapshot ready parent)
    (saved : slot.retained = some ⟨parent, data⟩) (changed : parent ≠ child) :
    (slot.read child).2.2 = false := by
  simp [LeanPoo.Functional.Requirements.ContextSlot.read, saved, changed]

-- A successful check is not reusable across an effect/source-change boundary.
theorem fresh_currentness_required (issued a b : Bool) :
    admissible issued false a b = false := changed_source_refused issued a b
end YuanxuProof.Admission.ReadRetention
