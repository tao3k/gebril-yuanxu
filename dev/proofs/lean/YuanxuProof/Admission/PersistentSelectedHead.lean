-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SerialUse
namespace YuanxuProof.Admission.PersistentSelectedHead

def quintSourceDigest : String :=
  "sha256:07e0866d4aa274ab26d852d5b0a50e0bb33dff8170ab0edf95798eae4ec8112a"

structure Head where
  revision : Nat
  fence : Nat
  selection : Nat
  snapshot : Nat
  deriving DecidableEq

structure Request where
  expected : Head
  target : Nat
  deriving DecidableEq

def commit (head : Head) (request : Request) : Option Head :=
  if head.revision = request.expected.revision ∧
     head.fence = request.expected.fence ∧
     head.selection = request.expected.selection then
    some {head with revision := head.revision + 1,
                    fence := head.fence + 1, snapshot := request.target}
  else none

theorem accepted_binds_revision_fence_selection (head : Head) (request : Request)
    (next : Head) (h : commit head request = some next) :
    head.revision = request.expected.revision ∧
    head.fence = request.expected.fence ∧
    head.selection = request.expected.selection := by
  unfold commit at h
  split at h
  · assumption
  · contradiction

theorem commit_updates_effect_with_fence (head : Head) (request : Request)
    (next : Head) (h : commit head request = some next) :
    next.snapshot = request.target ∧ next.revision = head.revision + 1 ∧
    next.fence = head.fence + 1 := by
  unfold commit at h
  split at h
  · cases h; exact ⟨rfl, rfl, rfl⟩
  · contradiction

theorem stale_revision_refused (head : Head) (request : Request)
    (h : head.revision ≠ request.expected.revision) : commit head request = none := by
  simp [commit, h]

theorem stale_fence_refused (head : Head) (request : Request)
    (h : head.fence ≠ request.expected.fence) : commit head request = none := by
  simp [commit, h]

-- Restart recovers the committed row; no new revision is invented on open.
def recover (persisted : Head) : Head := persisted
theorem restart_preserves_fence (head : Head) : (recover head).fence = head.fence := rfl

-- External source currentness is deliberately outside the stored-head relation.
-- Admission, artifact authentication and arbitrary remote effects are not proved here.
theorem source_not_a_commit_operand (head : Head) (request : Request) :
    commit (recover head) request = commit head request := rfl
end YuanxuProof.Admission.PersistentSelectedHead
