-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.ReadRetention
import Init.Data.List.Perm
import LeanPoo.Prototype.SlotSpec
import LeanPoo.Prototype.Representation

namespace YuanxuProof.ModuleSystem.Loading.PayloadSharing

-- Diagnostic retention projection, not admission and not a collector model.
-- A weak-key value is conditional on independent key liveness; the installed
-- collector correspondence must be established before using this as a heap bound.
inductive TablePolicy where
  | strong | weakKeys | weakValues | weakBoth
  deriving DecidableEq

def tableValueRetained (policy : TablePolicy) (keyLive : Bool) : Bool :=
  match policy with
  | .strong => true
  | .weakKeys => keyLive
  | .weakValues | .weakBoth => false

theorem weakKeyValueRequiresKey (live : Bool) :
    tableValueRetained .weakKeys live = true ↔ live = true := by rfl

theorem weakValueDoesNotRootValue (live : Bool) :
    tableValueRetained .weakValues live = false ∧
    tableValueRetained .weakBoth live = false := by exact ⟨rfl, rfl⟩

theorem keyLivenessMonotone (policy : TablePolicy) (before after : Bool)
    (growth : before = true → after = true)
    (retained : tableValueRetained policy before = true) :
    tableValueRetained policy after = true := by
  cases policy <;> simp_all [tableValueRetained]

-- The false inference under investigation: a table with weak keys can still
-- keep a value alive. Its container count alone says nothing about entry size.
theorem weakKeyIsNotWeakValue :
    tableValueRetained .weakKeys true ≠ tableValueRetained .weakValues true := by decide

-- A runtime inventory replaces queries, never a successful Type verdict.
-- Complete, unexposed inventory is a Scheme/MOP correspondence obligation.
theorem inventoryPresenceEquivalent (names required : List Nat)
    (present : Nat → Bool)
    (complete : ∀ name, present name = names.contains name) :
    required.all present = required.all (fun name => names.contains name) := by
  have same : present = fun name => names.contains name := funext complete
  rw [same]

def guardedInventory (eligible : Bool) (inventory ordinary : Unit → Bool) : Bool :=
  if eligible then inventory () else ordinary ()

theorem unownedOrOpenKeepsOrdinary (inventory ordinary : Unit → Bool) :
    guardedInventory false inventory ordinary = ordinary () := rfl

-- Every accepted field inventory must still pass the actual value predicate.
-- This is a shape optimization, not an admission or normalization cache.
theorem inventoryDoesNotAdmitRejectedValue (fields : Bool) :
    (fields && false) = false := by simp

-- Internal Core descriptors vary only these three VALUE fields. Persistent
-- runtime Storage.put owns the representation; no receiver cache is shared.
def coreDescriptor {Value : Type}
    (base : LeanPoo.Prototype.Representation.Storage Value)
    (id owner required : Value) :=
  ((base.put "feature-id" id).put "owner-module-id" owner).put "requires" required

theorem coreDescriptorIdentity {Value : Type}
    (base : LeanPoo.Prototype.Representation.Storage Value) (id owner required : Value) :
    LeanPoo.Prototype.Representation.first (coreDescriptor base id owner required).entries "feature-id" = some id := by
  unfold coreDescriptor
  rw [LeanPoo.Prototype.Representation.storage_put_frame _ "requires" "feature-id" required (by decide),
      LeanPoo.Prototype.Representation.storage_put_frame _ "owner-module-id" "feature-id" owner (by decide),
      LeanPoo.Prototype.Representation.storage_first_put]

theorem coreDescriptorDefaults {Value : Type}
    (base : LeanPoo.Prototype.Representation.Storage Value) (id owner required : Value)
    (name : String) (notId : name ≠ "feature-id")
    (notOwner : name ≠ "owner-module-id") (notRequired : name ≠ "requires") :
    LeanPoo.Prototype.Representation.first (coreDescriptor base id owner required).entries name =
      LeanPoo.Prototype.Representation.first base.entries name := by
  simp only [coreDescriptor,
    LeanPoo.Prototype.Representation.storage_put_frame _ _ _ _ notRequired,
    LeanPoo.Prototype.Representation.storage_put_frame _ _ _ _ notOwner,
    LeanPoo.Prototype.Representation.storage_put_frame _ _ _ _ notId]

theorem coreDescriptorOwner {Value : Type}
    (base : LeanPoo.Prototype.Representation.Storage Value) (id owner required : Value) :
    LeanPoo.Prototype.Representation.first (coreDescriptor base id owner required).entries "owner-module-id" = some owner := by
  unfold coreDescriptor
  rw [LeanPoo.Prototype.Representation.storage_put_frame _ "requires" "owner-module-id" required (by decide),
      LeanPoo.Prototype.Representation.storage_first_put]

theorem coreDescriptorRequirements {Value : Type}
    (base : LeanPoo.Prototype.Representation.Storage Value) (id owner required : Value) :
    LeanPoo.Prototype.Representation.first (coreDescriptor base id owner required).entries "requires" = some required := by
  exact LeanPoo.Prototype.Representation.storage_first_put _ _ _

-- Constructor arguments are evaluated Scheme values, not arbitrary slot
-- expressions. Only this closed case may use runtime lexical constant slots.
theorem constructorValueMethod {Receiver Value : Type} (value : Value) :
    (LeanPoo.Prototype.SlotSpec.self (fun (_ : Receiver) => value)).toMethod =
      (LeanPoo.Prototype.SlotSpec.constant value).toMethod := rfl

theorem constructorValueInComposition {Receiver Value : Type}
    (value : Value) (outer : LeanPoo.Prototype.Method Receiver Value)
    (receiver : Receiver) (inherited : LeanPoo.Prototype.Next Value) :
    LeanPoo.Prototype.Method.compose outer
      (LeanPoo.Prototype.SlotSpec.self (fun (_ : Receiver) => value)).toMethod receiver inherited =
    LeanPoo.Prototype.Method.compose outer
      (LeanPoo.Prototype.SlotSpec.constant value).toMethod receiver inherited := rfl

-- Runtime persistent snapshots already own their entry pairs. An internal
-- consumer can share that snapshot rather than round-trip through reflection.
-- This is ordered observation equality, NOT proof of raw-setter safety.
theorem snapshotReflectionRoundtrip {Value : Type}
    (source : LeanPoo.Prototype.Representation.Storage Value) :
    (LeanPoo.Prototype.Representation.packWith false source.entries).entries = source.entries := by
  exact LeanPoo.Prototype.Representation.entries_packWith false source.entries

-- Runtime object/init can select bounded compact storage for newly declared
-- methods/defaults without changing any ordered SlotSpec VALUE identity.
-- Bare prototype-map retains its explicit tree policy; this is constructor
-- lowering, not inference that arbitrary closures are pure.
theorem constructorStorageObservations {Value : Type}
    (methods defaults : List (String × Value)) :
    ((LeanPoo.Prototype.Representation.packWith true methods).entries,
     (LeanPoo.Prototype.Representation.packWith true defaults).entries) =
    ((LeanPoo.Prototype.Representation.packWith false methods).entries,
     (LeanPoo.Prototype.Representation.packWith false defaults).entries) := by
  simp

-- Upstream ae190d1 collects private rows without exporting intermediate public
-- snapshots. Prove the ENTIRE ordered carrier before any first-name policy:
-- duplicate occurrences and payload identities are not quotiented away here.
-- Vector/RBTree fold correspondence and final owned-pair capture remain runtime
-- obligations, checked by the upstream multi-root catalog controls.
theorem privateCatalogFoldOrder {Value : Type} (roots : List (List Value)) :
    roots.foldr (fun entries rest => entries.foldr List.cons rest) [] = roots.flatten := by
  have rows (entries rest : List Value) :
      entries.foldr List.cons rest = entries ++ rest := by
    induction entries with
    | nil => rfl
    | cons entry tail ih => simp [List.foldr, ih]
  induction roots with
  | nil => rfl
  | cons entries tail ih =>
    change entries.foldr List.cons
      (tail.foldr (fun entries rest => entries.foldr List.cons rest) []) = entries ++ tail.flatten
    rw [rows, ih]

-- Identifiers denote binding identity, not spelling or a user purity label.
def inject (original : Nat → Option Nat) (fresh binding : Nat) (name : Nat) : Option Nat :=
  if name = fresh then some binding else original name

theorem originalBindingUnchanged (original : Nat → Option Nat) (fresh binding name : Nat)
    (different : name ≠ fresh) : inject original fresh binding name = original name := by
  simp [inject, different]

theorem helperUsesCanonicalBinding (original : Nat → Option Nat) (fresh runtime : Nat) :
    inject original fresh runtime fresh = some runtime := by simp [inject]

-- Import projection changes a local binding index, never the runtime context,
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

theorem sameRuntimeContext (reader : Reader) (alias : Nat) :
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

-- Runtime slot-read checker compares the receiver's current instance identity.
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
-- Runtime identity-table enumeration must be duplicate-free; the runtime
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
-- An effective thunk is already observable through exported runtime metadata.
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

-- Apply ONLY after runtime identity deduplication. The classifier denotes an
-- observed support (for example, the actual language-context graph), not a
-- guessed exclusive owner. Opaque VM/code/table bodies remain unmeasured.
theorem weightedSupportPartition (identities : List Nat) (shared : Nat → Bool)
    (bodyBytes : Nat → Nat) :
    ((identities.filter shared).map bodyBytes).sum +
      ((identities.filter (fun id => !(shared id))).map bodyBytes).sum =
      (identities.map bodyBytes).sum := by
  induction identities with
  | nil => simp
  | cons id rest ih =>
    cases h : shared id <;> simp_all <;> omega

-- Core observes catalog emptiness and the first source-bearing declaration.
-- Reuse LeanPoo's storage refinement instead of a second representation model.
-- Runtime count/index correspondence and unforced inspection are runtime gates.
theorem catalogInspectionPreserved {Value : Type} (compact : Bool)
    (entries : List (String × Value)) (name : String) :
    (LeanPoo.Prototype.Representation.packWith compact entries).entries.isEmpty =
        entries.isEmpty ∧
      LeanPoo.Prototype.Representation.first
          (LeanPoo.Prototype.Representation.packWith compact entries).entries name =
        LeanPoo.Prototype.Representation.first entries name := by
  simp

-- Point lookup replaces an owned reflection list, not the source payload or
-- its presence. In particular, a present false declaration is still a barrier.
theorem metadataPresencePreserved {Value : Type} (compact : Bool)
    (entries : List (String × Value)) (name : String) :
    (LeanPoo.Prototype.Representation.first
      (LeanPoo.Prototype.Representation.packWith compact entries).entries name).isSome =
      (LeanPoo.Prototype.Representation.first entries name).isSome := by simp

theorem falseMetadataIsPresent (name : String) (tail : List (String × Bool)) :
    LeanPoo.Prototype.Representation.first ((name, false) :: tail) name = some false ∧
    (LeanPoo.Prototype.Representation.first ((name, false) :: tail) name).isSome = true := by
  simp [LeanPoo.Prototype.Representation.first]

-- Runtime compile-slot-specs may discard a prior chain only for these actual
-- constructors. A computed method remains open, regardless of its last value.
-- This is extensional SlotSpec semantics; runtime tests still own capture time,
-- invalid-input refusal, hook order and observable Scheme procedure identity.
def superIndependent {Self Value : Type}
    (spec : LeanPoo.Prototype.SlotSpec Self Value) : Prop :=
  match spec with
  | .computed _ => False
  | _ => True

-- The runtime names observer owns a copied spine, not another symbol order.
-- Record identity/revision/instance/observation and final issuer authentication
-- are separate conjuncts; value equivalence cannot establish any of them.
theorem copiedNamesPreserveProjection {Name Value : Type}
    (names : List Name) (project : Name → Value) :
    (names.map id).map project = names.map project := by simp

theorem namesEqualityDoesNotSupplyObservation (sameNames : Bool) :
    (sameNames && false) = false := by simp

theorem independentSpecificationDropsPrior {Self Value : Type}
    (spec : LeanPoo.Prototype.SlotSpec Self Value)
    (prior : LeanPoo.Prototype.Method Self Value)
    (independent : superIndependent spec) :
    LeanPoo.Prototype.Method.compose spec.toMethod prior = spec.toMethod := by
  cases spec with
  | constant _ => rfl
  | thunk _ => rfl
  | self _ => rfl
  | computed _ => exact False.elim independent

-- Nat denotes the actual byte-object identity, not string contents. An
-- identical private write can be omitted; a different identity still writes.
-- This proves lookup only. It does not establish diagnostic iteration order.
theorem identicalToolWritePreservesLookup
    (source : LeanPoo.Prototype.Representation.Storage Nat)
    (name queried : String) (value : Nat)
    (same : LeanPoo.Prototype.Representation.first source.entries name = some value) :
    LeanPoo.Prototype.Representation.first (source.put name value).entries queried =
      LeanPoo.Prototype.Representation.first source.entries queried := by
  by_cases equal : queried = name
  · subst queried
    rw [LeanPoo.Prototype.Representation.storage_first_put, same]
  · exact LeanPoo.Prototype.Representation.storage_put_frame source name queried value equal

def firstSourceDifference (rows : List (String × Nat))
    (current : String → Nat) : Option String :=
  (rows.find? (fun row => row.2 != current row.1)).map Prod.fst

-- A runtime experiment exposed exactly this missing implication: changing hash
-- table identity changed iteration order even for equal maps. Value proofs
-- cannot authorize a change to the first error or callback schedule.
theorem equalLookupCanChangeFirstDiagnostic :
    (∀ name : String,
      LeanPoo.Prototype.Representation.first [("a", 1), ("b", 2)] name =
        LeanPoo.Prototype.Representation.first [("b", 2), ("a", 1)] name) ∧
    firstSourceDifference [("a", 1), ("b", 2)] (fun _ => 0) ≠
      firstSourceDifference [("b", 2), ("a", 1)] (fun _ => 0) := by
  constructor
  · intro name
    by_cases a : name = "a"
    · subst name
      decide
    · by_cases b : name = "b"
      · subst name
        decide
      · simp [LeanPoo.Prototype.Representation.first, eq_comm, a, b]
  · decide

-- The new analysis protocol returns typed diagnostics, not per-datum admission
-- objects. Each Except is the projection of an actual fresh Type validation.
-- This model does not claim equivalence with arbitrary old receipt callbacks.
def collectDiagnostics {Error Diagnostic : Type} :
    List (Except Error (List Diagnostic)) → Except Error (List Diagnostic)
  | [] => .ok []
  | .error error :: _ => .error error
  | .ok issues :: tail => (collectDiagnostics tail).map (issues ++ ·)

theorem typedAnalysisPreservesOrder {Error Diagnostic : Type}
    (rows : List (List Diagnostic)) :
    collectDiagnostics (Error := Error) (rows.map Except.ok) = .ok rows.flatten := by
  induction rows with
  | nil => rfl
  | cons issues tail ih => simp [collectDiagnostics, ih, Except.map, List.flatten]

theorem analysisRefusalStopsAggregation {Error Diagnostic : Type}
    (error : Error) (tail : List (Except Error (List Diagnostic))) :
    collectDiagnostics (.error error :: tail) = .error error := rfl

theorem successfulPrefixCannotHideRefusal {Error Diagnostic : Type}
    (before : List (List Diagnostic)) (error : Error)
    (tail : List (Except Error (List Diagnostic))) :
    collectDiagnostics (before.map Except.ok ++ .error error :: tail) = .error error := by
  induction before with
  | nil => rfl
  | cons issues rest ih => simp [collectDiagnostics, ih, Except.map]

end YuanxuProof.ModuleSystem.Loading.PayloadSharing
