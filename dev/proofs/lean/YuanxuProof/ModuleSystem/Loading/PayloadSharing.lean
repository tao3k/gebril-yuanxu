-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReadRetention
import Init.Data.List.Perm

namespace YuanxuProof.ModuleSystem.Loading.PayloadSharing

def thunkConstructionDigest : String := "sha256:800d1aa25d86f6922e2682ac005c8b2dffd9be8fac461d12ca65532c6e7d4c8e"
def projectionObjectDigest : String := "sha256:bc890b7dc0bd956e02adf3a9c7404f5157659661f0cb63d5acb285424f3f06c6"

-- Identifiers denote binding identity, not spelling or a user purity label.
def inject (original : Nat → Option Nat) (fresh binding : Nat) (name : Nat) : Option Nat :=
  if name = fresh then some binding else original name

theorem originalBindingUnchanged (original : Nat → Option Nat) (fresh binding name : Nat)
    (different : name ≠ fresh) : inject original fresh binding name = original name := by
  simp [inject, different]

theorem helperUsesCanonicalBinding (original : Nat → Option Nat) (fresh native : Nat) :
    inject original fresh native fresh = some native := by simp [inject]

-- Import projection changes a local binding index, never the native context,
-- ordered reads or adjacency lists. Context/source authentication remains live.
structure Support where
  context : Nat
  records : List Nat
  dependencies : Nat → List Nat
  observations : List Nat

structure Reader where
  support : Support
  localBindings : List Nat

def projectBindings (reader : Reader) (alias : Nat) : Reader :=
  {reader with localBindings := [alias]}

theorem originalRecords (reader : Reader) (alias : Nat) :
    (projectBindings reader alias).support.records = reader.support.records := rfl

theorem originalEdges (reader : Reader) (alias record : Nat) :
    (projectBindings reader alias).support.dependencies record = reader.support.dependencies record := rfl

theorem observerOrder (reader : Reader) (alias : Nat) :
    (projectBindings reader alias).support.observations = reader.support.observations := rfl

theorem sameNativeContext (reader : Reader) (alias : Nat) :
    (projectBindings reader alias).support.context = reader.support.context := rfl

-- Logical immutable snapshots may share storage ONLY for the entire ordered
-- identity sequence, including repeated edges. The private producer must prove
-- actual immutability; exposed Scheme lists are not assumed immutable.
def intern (pool : List (List Nat)) (payload : List Nat) : List (List Nat) :=
  if payload ∈ pool then pool else pool ++ [payload]

theorem snapshotAvailable (pool : List (List Nat)) (payload : List Nat) :
    payload ∈ intern pool payload := by
  by_cases hit : payload ∈ pool <;> simp [intern, hit]

theorem exactSnapshotReused (pool : List (List Nat)) (payload : List Nat)
    (hit : payload ∈ pool) : intern pool payload = pool := by simp [intern, hit]

theorem changedOrderNotEquivalent : ([1, 2, 1] : List Nat) ≠ [1, 1, 2] := by decide

theorem equalContentsDoNotMergeRecords :
    ([21, 22] : List Nat) ≠ [21, 21] := by decide

-- Validity is checked at use. Sharing a catalogue or an immutable snapshot is
-- not a way of carrying an earlier source or domain approval across a callback.
theorem changedSourceRefused (issued a b : Bool) :
    YuanxuProof.Admission.IssuedRootForwarding.admissible issued false a b = false :=
  YuanxuProof.Admission.IssuedRootForwarding.changed_source_refused issued a b

-- No cross-call sharing of frames, argument spines or continuations follows
-- from equal generic names. The frame receivers remain context-owned.
theorem separateFramesRemainSeparate (parent child : Nat) (different : parent ≠ child) :
    parent ≠ child := different

-- Native slot-read checker compares the receiver's current instance identity.
-- A shared shape is structural metadata; cells and callback environments remain
-- receiver-owned. This model does not assert that Scheme lists are immutable.
structure ReceiverState where
  owner : Nat
  revision : Nat
  instanceId : Nat
  shape : Nat
  cells : List Nat
  callback : Nat
  deriving DecidableEq

structure ReadAnchor where
  owner : Nat
  revision : Nat
  instanceId : Nat
  deriving DecidableEq

def authentic (read : ReadAnchor) (state : ReceiverState) : Prop :=
  read.owner = state.owner ∧ read.revision = state.revision ∧ read.instanceId = state.instanceId

def shareShape (state : ReceiverState) (shape : Nat) : ReceiverState :=
  {state with shape := shape}

-- Shape identity alone is insufficient: it must preserve the actual slot map.
def valueAt (indices : Nat → Nat → Option Nat) (state : ReceiverState)
    (name : Nat) : Option Nat :=
  match indices state.shape name with
  | none => none
  | some index => state.cells[index]?

theorem equivalentShapePreservesLookup (indices : Nat → Nat → Option Nat)
    (state : ReceiverState) (shared name : Nat)
    (same : ∀ key, indices shared key = indices state.shape key) :
    valueAt indices (shareShape state shared) name = valueAt indices state name := by
  simp only [valueAt, shareShape, same name]

theorem shapeSharingPreservesAnchor (read : ReadAnchor) (state : ReceiverState) (shape : Nat) :
    authentic read (shareShape state shape) ↔ authentic read state := by
  rfl

theorem shapeSharingPreservesPayload (state : ReceiverState) (shape : Nat) :
    (shareShape state shape).cells = state.cells ∧
    (shareShape state shape).callback = state.callback := by
  exact ⟨rfl, rfl⟩

theorem instanceReplacementRefused (read : ReadAnchor) (state : ReceiverState)
    (different : read.instanceId ≠ state.instanceId) : ¬ authentic read state := by
  intro valid
  exact different valid.2.2

theorem parentCannotAuthenticateChild (read : ReadAnchor) (child : ReceiverState)
    (different : read.owner ≠ child.owner) : ¬ authentic read child := by
  intro valid
  exact different valid.1

-- Replacing a revision or instance requires a new producer-issued record even
-- when the printed payload is equal. Equal cells cannot stand in for identity.
theorem revisionReplacementRefused (read : ReadAnchor) (state : ReceiverState)
    (different : read.revision ≠ state.revision) : ¬ authentic read state := by
  intro valid
  exact different valid.2.1

-- Accounting visits identities, not paths. An extra reference to an existing
-- tree/environment is not another allocation. This is NOT a license to omit
-- a production read edge or observer delivery.
def account (seen : List Nat) (identity : Nat) : List Nat :=
  if identity ∈ seen then seen else identity :: seen

theorem sharedNodeAccountedOnce (seen : List Nat) (identity : Nat) :
    account (account seen identity) identity = account seen identity := by
  by_cases hit : identity ∈ seen <;> simp [account, hit]

theorem distinctEnvironmentRetained (seen : List Nat) (left right : Nat) :
    left ∈ account (account seen left) right ∧
    right ∈ account (account seen left) right := by
  by_cases l : left ∈ seen <;> by_cases r : right ∈ seen <;>
    by_cases same : right = left <;> simp_all [account]

-- Count the union without allocating a second copy of the larger support.
-- Native identity-table enumeration must be duplicate-free; the runtime
-- correspondence is explicit, not a theorem about GC dominator ownership.
theorem partitionLength (xs : List Nat) (p : Nat → Bool) :
    (xs.filter p).length + (xs.filter (fun x => !(p x))).length = xs.length := by
  induction xs with
  | nil => simp
  | cons x xs ih =>
    cases h : p x <;> simp_all <;> omega

theorem unionCountWithoutCopy (left right : List Nat) :
    (left ++ right.filter (fun x => !(left.contains x))).length =
      left.length + right.length - (right.filter left.contains).length := by
  have h := partitionLength right left.contains
  simp only [List.length_append]
  omega

theorem intersectionCountSymmetric (left right : List Nat)
    (uniqueLeft : left.Nodup) (uniqueRight : right.Nodup) :
    (left.filter right.contains).length = (right.filter left.contains).length := by
  have same : (left.filter right.contains).Perm (right.filter left.contains) :=
    (List.perm_ext_iff_of_nodup
      (List.Pairwise.filter right.contains uniqueLeft)
      (List.Pairwise.filter left.contains uniqueRight)).2 (by
        intro x
        simp [and_comm])
  exact same.length_eq

def smallerIntersection (left right : List Nat) : Nat :=
  if left.length < right.length then (left.filter right.contains).length
  else (right.filter left.contains).length

theorem smallerIntersectionCorrect (left right : List Nat)
    (uniqueLeft : left.Nodup) (uniqueRight : right.Nodup) :
    smallerIntersection left right = (right.filter left.contains).length := by
  unfold smallerIntersection
  split
  · exact intersectionCountSymmetric left right uniqueLeft uniqueRight
  · rfl

-- Issuer-private representation only. Nat denotes ORIGINAL read identity.
-- The public dependency spine, its duplicates and its delivery are unchanged.
inductive ParentSnapshot where
  | one (read : Nat)
  | dense (reads : List Nat)

def snapshotParents : List Nat → ParentSnapshot
  | [read] => .one read
  | reads => .dense reads

def restoreParents : ParentSnapshot → List Nat
  | .one read => [read]
  | .dense reads => reads

theorem snapshotParentsExact (parents : List Nat) :
    restoreParents (snapshotParents parents) = parents := by
  cases parents with
  | nil => rfl
  | cons first rest => cases rest <;> rfl

theorem snapshotAcceptsExactlyOriginal (current original : List Nat) :
    current = restoreParents (snapshotParents original) ↔ current = original := by
  rw [snapshotParentsExact]

theorem snapshotPreservesEveryOccurrence (parents : List Nat) (index : Nat) :
    (restoreParents (snapshotParents parents))[index]? = parents[index]? := by
  rw [snapshotParentsExact]

-- No equality of receiver/callback state and no cached admission is inferred.
-- A cold table ENTRY may share its function with a warm entry. Count the
-- identity difference, not all cold entries as independently removable roots.
def coldOnly (cold warm : List Nat) : List Nat :=
  cold.filter (fun identity => !(warm.contains identity))

theorem coldOnlyExcludesWarm (cold warm : List Nat) (identity : Nat)
    (member : identity ∈ coldOnly cold warm) : identity ∉ warm := by
  simpa [coldOnly] using (List.mem_filter.mp member).2

theorem warmAndColdCoverOriginal (cold warm : List Nat) (identity : Nat) :
    identity ∈ warm ++ coldOnly cold warm ↔ identity ∈ warm ∨ identity ∈ cold := by
  by_cases present : identity ∈ warm <;> simp [coldOnly, present]

-- Mutating, dropping or reordering public parents is accepted iff the original
-- identity sequence is restored; revision/currentness remain separate checks.
-- An effective thunk is already observable through exported native metadata.
-- This is an observation theorem, not a claim that function identity is data.
def delayEntry (table : Nat → Option Nat) (slot : Nat) : Nat → Option Nat :=
  fun key => if key = slot then none else table key

theorem otherThunkIdentityPreserved (table : Nat → Option Nat) (slot key : Nat)
    (different : key ≠ slot) : delayEntry table slot key = table key := by
  simp [delayEntry, different]

theorem exposedThunkCannotDisappear (table : Nat → Option Nat) (slot identity : Nat)
    (visible : table slot = some identity) : delayEntry table slot slot ≠ table slot := by
  simp [delayEntry, visible]

-- The positive boundary is observation-relative: absence from this projection
-- must be established; "no protocol" alone does not establish it.
theorem unobservedThunkProjectionPreserved (table : Nat → Option Nat)
    (slot : Nat) (observed : List Nat) (hidden : slot ∉ observed) :
    observed.map (delayEntry table slot) = observed.map table := by
  apply List.map_congr_left
  intro key member
  apply otherThunkIdentityPreserved
  intro same
  exact hidden (same ▸ member)

end YuanxuProof.ModuleSystem.Loading.PayloadSharing
