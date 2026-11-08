-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission

namespace YuanxuProof.ModuleSystem.Graph.PublicationReads
open TestAdmission

-- Identity normalization preserves the full original suffix. No assumption
-- about callback purity, Contract identity labels or token payload equality.
theorem same_roots_same_demands (deps : α → List α) (left right : List α)
    (same : ∀ node, node ∈ left ↔ node ∈ right) (node : α) :
    Demanded deps left node ↔ Demanded deps right node := by
  constructor
  · intro demand
    induction demand with
    | root node member => exact Demanded.root node ((same node).mp member)
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge
  · intro demand
    induction demand with
    | root node member => exact Demanded.root node ((same node).mpr member)
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge

theorem dedup_preserves_demands [BEq α] [LawfulBEq α]
    (deps : α → List α) (roots : List α) (node : α) :
    Demanded deps roots node ↔ Demanded deps roots.eraseDups node := by
  apply same_roots_same_demands
  intro node
  simp

def Current (deps : α → List α) (roots : List α) (fresh : α → Prop) : Prop :=
  ∀ node, Demanded deps roots node → fresh node

theorem dedup_preserves_currentness [BEq α] [LawfulBEq α]
    (deps : α → List α) (roots : List α) (fresh : α → Prop) :
    Current deps roots fresh ↔ Current deps roots.eraseDups fresh := by
  constructor
  · intro current node demanded
    exact current node ((dedup_preserves_demands deps roots node).mpr demanded)
  · intro current node demanded
    exact current node ((dedup_preserves_demands deps roots node).mp demanded)

-- An authenticated traversal's issued descendants are already part of the
-- original roots' obligations. This law concerns demand and freshness only.
-- An open observer must still receive every original occurrence in order.
theorem replay_of_issued_descendants_has_same_demands
    (deps : Node → List Node) (roots descendants : List Node)
    (issued : ∀ node ∈ descendants, Demanded deps roots node) (node : Node) :
    Demanded deps (roots ++ descendants) node ↔ Demanded deps roots node := by
  constructor
  · intro demand
    induction demand with
    | root node member =>
      rcases List.mem_append.mp member with original | derived
      · exact Demanded.root node original
      · exact issued node derived
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge
  · intro demand
    induction demand with
    | root node member => exact Demanded.root node (List.mem_append_left _ member)
    | dependency parent child _ edge ih => exact Demanded.dependency parent child ih edge

theorem replay_of_issued_descendants_has_same_currentness
    (deps : Node → List Node) (roots descendants : List Node)
    (issued : ∀ node ∈ descendants, Demanded deps roots node) (fresh : Node → Prop) :
    Current deps (roots ++ descendants) fresh ↔ Current deps roots fresh := by
  constructor
  · intro current node demand
    exact current node ((replay_of_issued_descendants_has_same_demands
      deps roots descendants issued node).mpr demand)
  · intro current node demand
    exact current node ((replay_of_issued_descendants_has_same_demands
      deps roots descendants issued node).mp demand)

-- Native re-observation has an issuance preflight followed by delivery.
-- A stale maintained method may route to the Generic during preflight.
-- Once delivery begins its refusal belongs to that invocation.
inductive DispatchOutcome (Failure Result : Type) where
  | generic
  | refused (cause : Failure)
  | returned (value : Result)
  deriving DecidableEq

def stockDelivery {Failure Result : Type} (ready : Bool)
    (delivery : Except Failure Result) : DispatchOutcome Failure Result :=
  if ready then
    match delivery with
    | .error cause => .refused cause
    | .ok value => .returned value
  else .generic

def splitDispatch {Failure Result : Type} (firstCheck nextCheck payload method : Bool)
    (delivery : Except Failure Result) (stale : Failure) : DispatchOutcome Failure Result :=
  if firstCheck && payload && method then
    if nextCheck then stockDelivery true delivery else .refused stale
  else .generic

def joinedDispatch {Failure Result : Type} (nativeCheck payload method : Bool)
    (delivery : Except Failure Result) : DispatchOutcome Failure Result :=
  stockDelivery (nativeCheck && payload && method) delivery

theorem join_preflight_in_same_read_state {Failure Result : Type}
    (firstCheck nextCheck payload method : Bool)
    (unchanged : firstCheck = nextCheck)
    (delivery : Except Failure Result) (stale : Failure) :
    joinedDispatch nextCheck payload method delivery =
      splitDispatch firstCheck nextCheck payload method delivery stale := by
  subst nextCheck
  cases firstCheck <;> cases payload <;> cases method <;> rfl

theorem joined_does_not_retry_a_delivery_failure {Failure Result : Type} (cause : Failure) :
    joinedDispatch (Result := Result) true true true (.error cause) = .refused cause := rfl

def authenticateAndVisit {Read Failure : Type} (auth : Read → Except Failure Unit)
    (visit : Read → Unit) : List Read → Except Failure Unit
  | [] => .ok ()
  | read :: rest => do
      auth read
      let () := visit read
      authenticateAndVisit auth visit rest

theorem no_observer_authenticates_the_same_order
    {Read Failure : Type} (auth : Read → Except Failure Unit)
    (visit : Read → Unit) (reads : List Read) :
    authenticateAndVisit auth visit reads = authenticateAndVisit auth (fun _ => ()) reads := by
  induction reads with
  | nil => rfl
  | cons read rest ih => simp only [authenticateAndVisit, ih]

def readWindow {Read Failure Result : Type}
    (before after : Read → Except Failure Unit) (visit : Read → Unit)
    (reads : List Read) (action : Except Failure Result) : Except Failure Result := do
  authenticateAndVisit before visit reads
  let result ← action
  authenticateAndVisit after (fun _ => ()) reads
  pure result

theorem read_only_checkpoint_preserves_both_refusals
    {Read Failure Result : Type}
    (before after : Read → Except Failure Unit) (visit : Read → Unit)
    (reads : List Read) (action : Except Failure Result) :
    readWindow before after visit reads action =
      readWindow before after (fun _ => ()) reads action := by
  unfold readWindow
  rw [no_observer_authenticates_the_same_order before visit reads]

-- Source preparation consumes only the first diagnostic. The public API
-- still returns and validates its receipt. A closed empty result has no
-- diagnostic whose Type could run, but the maintained aggregate validator
-- and the actual owner/role field reads must both be established.
structure SourceAuthoringReceipt (Owner Role Diagnostic : Type) where
  owner : Owner
  role : Role
  diagnostics : List Diagnostic
  accepted : Bool
  runtimeExecuted : Bool

def stockAuthoringReceipt {Owner Role Diagnostic : Type} (owner : Owner) (role : Role)
    (diagnostics : List Diagnostic) : SourceAuthoringReceipt Owner Role Diagnostic :=
  ⟨owner, role, diagnostics, diagnostics.isEmpty, false⟩

def stockReceiptShape {Owner Role Diagnostic : Type}
    (ownerValid : Owner → Bool) (roleValid : Role → Bool) (diagnosticValid : Diagnostic → Bool)
    (receipt : SourceAuthoringReceipt Owner Role Diagnostic) : Bool :=
  ownerValid receipt.owner && roleValid receipt.role &&
    (receipt.accepted == receipt.diagnostics.isEmpty) &&
    !receipt.runtimeExecuted && receipt.diagnostics.all diagnosticValid

theorem empty_stock_receipt_valid
    {Owner Role Diagnostic : Type} (ownerValid : Owner → Bool) (roleValid : Role → Bool)
    (diagnosticValid : Diagnostic → Bool) (owner : Owner) (role : Role)
    (ownerChecked : ownerValid owner = true) (roleChecked : roleValid role = true) :
    stockReceiptShape ownerValid roleValid diagnosticValid
      (stockAuthoringReceipt owner role []) = true := by
  simp [stockReceiptShape, stockAuthoringReceipt, ownerChecked, roleChecked]

def consumeSourceReceipt {Owner Role Diagnostic Failure : Type}
    (validate : SourceAuthoringReceipt Owner Role Diagnostic →
      Except Failure (SourceAuthoringReceipt Owner Role Diagnostic))
    (receipt : SourceAuthoringReceipt Owner Role Diagnostic) :
    Except Failure (Option Diagnostic) := do
  let checked ← validate receipt
  pure (if checked.accepted then none else checked.diagnostics.head?)

def sourceOnlyReceipt {Owner Role Diagnostic Failure : Type}
    (closed : Bool)
    (validate : SourceAuthoringReceipt Owner Role Diagnostic →
      Except Failure (SourceAuthoringReceipt Owner Role Diagnostic))
    (receipt : SourceAuthoringReceipt Owner Role Diagnostic) :
    Except Failure (Option Diagnostic) :=
  if closed && receipt.diagnostics.isEmpty then .ok none
  else consumeSourceReceipt validate receipt

theorem source_only_preserves_closed_empty_receipt
    {Owner Role Diagnostic Failure : Type}
    (validate : SourceAuthoringReceipt Owner Role Diagnostic →
      Except Failure (SourceAuthoringReceipt Owner Role Diagnostic))
    (owner : Owner) (role : Role)
    (maintained : validate (stockAuthoringReceipt owner role []) =
      .ok (stockAuthoringReceipt owner role [])) :
    sourceOnlyReceipt true validate (stockAuthoringReceipt owner role []) =
      consumeSourceReceipt validate (stockAuthoringReceipt owner role []) := by
  simp only [sourceOnlyReceipt, consumeSourceReceipt, maintained]
  rfl

theorem source_only_preserves_open_receipt
    {Owner Role Diagnostic Failure : Type}
    (validate : SourceAuthoringReceipt Owner Role Diagnostic →
      Except Failure (SourceAuthoringReceipt Owner Role Diagnostic))
    (receipt : SourceAuthoringReceipt Owner Role Diagnostic) :
    sourceOnlyReceipt false validate receipt = consumeSourceReceipt validate receipt := rfl

-- Separate snapshots can disagree. The equality applies only to a single
-- authenticated pre-delivery read, never across an author call.
example : joinedDispatch (Result := Nat) false true true (.ok 1) ≠
    splitDispatch true false true true (.ok 1) "changed" := by decide

/-- Only the expander's closed stock projection in a private interpreter
wrapper may deliver directly. An open or compiled declaration uses its binding. -/
def directDelivery (privateWrapper stock : Bool) : Bool := privateWrapper && stock

structure WrapperDelivery (Owner Payload : Type) where
  owner : Owner
  payload : Payload

def acceptWrapperDelivery [DecidableEq Owner] (expected : Owner)
    (pending : Option (WrapperDelivery Owner Payload)) (offered : WrapperDelivery Owner Payload) :
    Option (WrapperDelivery Owner Payload) :=
  if offered.owner = expected ∧ pending.isNone then some offered else none

theorem wrapper_delivery_is_exact [DecidableEq Owner] (owner : Owner) (payload : Payload) :
    acceptWrapperDelivery owner none ⟨owner, payload⟩ = some ⟨owner, payload⟩ := by
  simp [acceptWrapperDelivery]

theorem foreign_wrapper_cannot_deliver [DecidableEq Owner]
    (expected : Owner) (offered : WrapperDelivery Owner Payload) (foreign : offered.owner ≠ expected) :
    acceptWrapperDelivery expected none offered = none := by
  simp [acceptWrapperDelivery, foreign]

theorem repeated_wrapper_cannot_deliver [DecidableEq Owner]
    (owner : Owner) (old offered : WrapperDelivery Owner Payload) :
    acceptWrapperDelivery owner (some old) offered = none := by
  simp [acceptWrapperDelivery]

def readDeliveredPublication {Failure Payload Result : Type}
    (before native after : Except Failure Unit) (payload : Except Failure Payload)
    (admit : Payload → Except Failure Result) : Except Failure Result := do
  before
  native
  let value ← payload
  after
  admit value

/-- The same payload moves from its native initializer into the reader.
The external observer still sees the same refusal order. -/
theorem closed_delivery_preserves_checks [DecidableEq Owner]
    (owner : Owner) (value : Payload) (missing : Failure)
    (before native after : Except Failure Unit) (admit : Payload → Except Failure Result) :
    readDeliveredPublication before native after
        (match acceptWrapperDelivery owner none ⟨owner, value⟩ with
        | some delivery => .ok delivery.payload
        | none => .error missing) admit =
      readDeliveredPublication before native after (.ok value) admit := by
  rw [wrapper_delivery_is_exact]

theorem no_direct_delivery_for_open_or_compiled (privateWrapper stock : Bool)
    (openOrCompiled : privateWrapper = false ∨ stock = false) :
    directDelivery privateWrapper stock = false := by
  rcases openOrCompiled with h | h <;> simp [directDelivery, h]

/-- Ordered guards over the same read state. The authenticator supplies the
same observation for every lane, including the first refusal. -/
def authenticateLanes (auth : Read → Except Failure Unit) :
    List (List Read) → Except Failure Unit
  | [] => .ok ()
  | reads :: lanes => do
    authenticateAndVisit auth (fun _ => ()) reads
    authenticateLanes auth lanes

theorem authenticate_append (auth : Read → Except Failure Unit) (left right : List Read) :
    authenticateAndVisit auth (fun _ => ()) (left ++ right) = (do
      authenticateAndVisit auth (fun _ => ()) left
      authenticateAndVisit auth (fun _ => ()) right) := by
  induction left with
  | nil => rfl
  | cons read rest ih =>
    simp only [List.cons_append, authenticateAndVisit]
    cases auth read with
    | error => rfl
    | ok => exact ih

theorem same_window_preserves_first_refusal
    (auth : Read → Except Failure Unit) (lanes : List (List Read)) :
    authenticateAndVisit auth (fun _ => ()) lanes.flatten = authenticateLanes auth lanes := by
  induction lanes with
  | nil => rfl
  | cons reads rest ih =>
    simp only [List.flatten_cons, authenticate_append, authenticateLanes, ih]

-- Nesting protected checks unwinds the last lane first. A shared topology
-- cannot justify reversing the original return authentication when more than
-- one lane can independently refuse.
theorem nested_lane_return_can_change_first_refusal :
    let auth (read : Nat) : Except Nat Unit := .error read
    authenticateLanes auth [[0], [1]] ≠ authenticateLanes auth [[1], [0]] := by
  dsimp only
  intro same
  change (Except.error 0 : Except Nat Unit) = .error 1 at same
  cases same

/-- Reusing an issued token's identity supplies no equality of observations
across an effect. The after-check can refuse the very same token. -/
example :
    readWindow (fun (_ : Nat) => (.ok () : Except String Unit))
        (fun _ => .error "changed") (fun _ => ()) [7] (.ok 9) =
      .error "changed" := rfl

/-- The stock Profile may retain a spine naming a signed singleton root.
Selection compares record identity, and never remembers the guard outcome. -/
def profileCheckpointRoots [DecidableEq Read] (observed retained : List Read) : List Read :=
  match observed, retained with
  | [current], [previous] => if current = previous then retained else observed
  | _, _ => observed

theorem profile_checkpoint_preserves_issued_order [DecidableEq Read]
    (observed retained : List Read) : profileCheckpointRoots observed retained = observed := by
  cases observed with
  | nil => rfl
  | cons current observed =>
    cases observed with
    | cons _ _ => rfl
    | nil =>
      cases retained with
      | nil => rfl
      | cons previous retained =>
        cases retained with
        | cons _ _ => rfl
        | nil =>
          simp only [profileCheckpointRoots]
          split <;> simp_all

theorem profile_checkpoint_keeps_fresh_refusal [DecidableEq Read]
    (auth : Read → Except Failure Unit) (observed retained : List Read) :
    authenticateAndVisit auth (fun _ => ()) (profileCheckpointRoots observed retained) =
      authenticateAndVisit auth (fun _ => ()) observed := by
  rw [profile_checkpoint_preserves_issued_order]

-- The same Profile root may occur in every owner's preparation. If a live
-- check of its native token refuses, authenticating all other reads can
-- still succeed. A replacement must account for the Profile's own support.
theorem profile_omission_can_hide_native_refusal
    (auth : Read → Except Failure Unit) (before after : List Read)
    (profile : Read) (stale : Failure)
    (beforeOk : authenticateAndVisit auth (fun _ => ()) before = .ok ())
    (afterOk : authenticateAndVisit auth (fun _ => ()) after = .ok ())
    (profileStale : auth profile = .error stale) :
    authenticateAndVisit auth (fun _ => ()) (before ++ profile :: after) = .error stale ∧
    authenticateAndVisit auth (fun _ => ()) (before ++ after) = .ok () := by
  simp only [authenticate_append, beforeOk, afterOk, authenticateAndVisit, profileStale,
    Except.bind, bind, and_self]

-- Projecting a producer's internal proof requires its actual retained
-- preorder, not just a receiver tag or the checked value's identity.
theorem private_reads_preserve_external_refusal
    (auth : Read → Except Failure Unit) (keep : Read → Bool) (reads : List Read)
    (privateCurrent : ∀ read, keep read = false → auth read = .ok ()) :
    authenticateAndVisit auth (fun _ => ()) (reads.filter keep) =
      authenticateAndVisit auth (fun _ => ()) reads := by
  induction reads with
  | nil => rfl
  | cons read rest ih =>
    cases kept : keep read with
    | false => simp [kept, authenticateAndVisit, privateCurrent read kept, ih, Except.bind, bind]
    | true => simp [kept, authenticateAndVisit, ih]

-- The producer must discharge privacy/currentness at BOTH sides of an
-- effect. The currentness of the kept reads is always checked anew.
theorem projected_private_read_window
    (before after : Read → Except Failure Unit) (keep : Read → Bool)
    (reads projected : List Read) (action : Except Failure Result)
    (exactOrder : projected = reads.filter keep)
    (privateBefore : ∀ read, keep read = false → before read = .ok ())
    (privateAfter : ∀ read, keep read = false → after read = .ok ()) :
    readWindow before after (fun _ => ()) projected action =
      readWindow before after (fun _ => ()) reads action := by
  subst projected
  simp only [readWindow, private_reads_preserve_external_refusal before keep reads privateBefore,
    private_reads_preserve_external_refusal after keep reads privateAfter]

/-- The two original native spines remain separate until a checkpoint needs
their concatenation. Neither phase's issued records are reconstructed. -/
def rootSegments (row : List Read × List Read) : List (List Read) := [row.1, row.2]

theorem flatten_root_segments (rows : List (List Read × List Read)) :
    (rows.flatMap rootSegments).flatten =
      (rows.map fun row => row.1 ++ row.2).flatten := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    simp [rootSegments, ih, List.append_assoc]

theorem segmented_roots_preserve_first_refusal
    (auth : Read → Except Failure Unit) (rows : List (List Read × List Read)) :
    authenticateAndVisit auth (fun _ => ()) (rows.flatMap rootSegments).flatten =
      authenticateAndVisit auth (fun _ => ()) (rows.map fun row => row.1 ++ row.2).flatten := by
  rw [flatten_root_segments]

-- Runtime correspondence premises remain: eq?-identity normalization,
-- unmodified original dependency lists, public replay's final recheck,
-- unchanged real observer delivery, and no nonlocal continuation escape.
-- This does not prove toolchain ownership, GC behavior or a memory byte bound.
-- Each result carries its own ordered read delivery. Fixed support can be
-- authenticated once for a closed run of these independently evaluated rows.
def checkStockEach {Failure Result : Type} (check : Except Failure Unit) :
    List (Except Failure Result) → Except Failure (List Result)
  | [] => .ok []
  | result :: rest => do
      check
      let value ← result
      let values ← checkStockEach check rest
      pure (value :: values)

def checkStockRun {Failure Result : Type} (check : Except Failure Unit)
    (stock : List (Except Failure Result)) : Except Failure (List Result) :=
  match stock with
  | [] => .ok []
  | _ :: _ => do
      check
      checkStockEach (.ok ()) stock

theorem unchanged_stock_support_preserves_results_and_refusal
    (check : Except Failure Unit) (stock : List (Except Failure Result)) :
    checkStockRun check stock = checkStockEach check stock := by
  cases check <;> cases stock <;> rfl

-- The author call owns two fresh guards. The next closed run consumes the
-- post-effect state, even if the previous run had valid support.
def stockAroundOpen {World Failure Result : Type}
    (run : Except Failure Unit → List (Except Failure Result) → Except Failure (List Result))
    (check : World → Except Failure Unit) (author : World → World)
    (left right : World → List (Except Failure Result)) (start : World) :
    Except Failure (List Result × List Result × World) := do
  let first ← run (check start) (left start)
  check start
  let current := author start
  check current
  let last ← run (check current) (right current)
  pure (first, last, current)

theorem stock_runs_preserve_independent_open_checks
    (check : World → Except Failure Unit) (author : World → World)
    (left right : World → List (Except Failure Result)) (start : World) :
    stockAroundOpen checkStockRun check author left right start =
      stockAroundOpen checkStockEach check author left right start := by
  simp only [stockAroundOpen, unchanged_stock_support_preserves_results_and_refusal]

example : stockAroundOpen (Result := Nat) checkStockRun
    (fun changed => if changed then .error "stale method" else .ok ())
    (fun _ => true) (fun _ => List.replicate 9 (.ok 1)) (fun _ => []) false =
      .error "stale method" := rfl

-- A native replay authenticates before and after its protected action.
-- For the factory's callback-free directory check, put the original
-- location and leading policy between those same endpoints. Keep the
-- trailing policy after the final authentication.
def replayCheckpoint {Failure : Type} (before action after : Except Failure Unit) :
    Except Failure Unit := do
  before
  action
  after

def separateReaderEntry {Failure : Type}
    (before location policy after trailing : Except Failure Unit) : Except Failure Unit := do
  replayCheckpoint before (.ok ()) before
  location
  policy
  replayCheckpoint after (.ok ()) after
  trailing

def fusedReaderEntry {Failure : Type}
    (before location policy after trailing : Except Failure Unit) : Except Failure Unit := do
  replayCheckpoint before (do location; policy) after
  trailing

theorem directory_entry_preserves_refusal
    (before location policy after trailing : Except Failure Unit) :
    fusedReaderEntry before location policy after trailing =
      separateReaderEntry before location policy after trailing := by
  cases before <;> cases location <;> cases policy <;> cases after <;> rfl

theorem directory_entry_keeps_post_location_refusal {Failure : Type} (stale : Failure) :
    fusedReaderEntry (.ok ()) (.ok ()) (.ok ()) (.error stale) (.ok ()) = .error stale := rfl

-- The fusion never replaces the independent checkpoint after a Gerbil or
-- author effect. A successful entry grants no authority over the next state.
theorem fused_directory_entry_cannot_bless_open_return {Failure : Type} (stale : Failure) :
    (do
      fusedReaderEntry (.ok ()) (.ok ()) (.ok ()) (.ok ()) (.ok ())
      (.error stale : Except Failure Unit)) = .error stale := rfl

-- Only the inert datum read from the same captured Interface bytes is shared.
-- Owner binding, native identity admission and post-expansion validation retain
-- independent inputs and first-refusal order.
theorem interface_datum_read_preserves_owner_and_refusals
    {Failure Forms Owner Identity Roles : Type}
    (parsed : Except Failure Forms) (binding : Forms → Except Failure Owner)
    (nativeIdentity : Owner → Except Failure Identity)
    (classify : Forms → Option Roles)
    (afterExpansion : Identity → Except Failure Unit) :
    (do
      let forms ← parsed
      let owner ← binding forms
      let identity ← nativeIdentity owner
      let roles := classify forms
      afterExpansion identity
      pure (owner, identity, roles)) =
    (do
      let forms ← parsed
      let owner ← binding forms
      let identity ← nativeIdentity owner
      let forms ← parsed
      let roles := classify forms
      afterExpansion identity
      pure (owner, identity, roles)) := by
  cases parsed with
  | error => rfl
  | ok forms =>
    cases binding forms with
    | error => rfl
    | ok owner => cases nativeIdentity owner <;> rfl

-- This models the same closed interval, with live replay inputs. The first
-- read set predates declaration admission; the second is what admission read.
def candidateReturnInOrder {Failure : Type}
    (prepared source admitted : Except Failure Unit) : Except Failure Unit := do
  prepared
  source
  admitted

def candidateReturnWithPreflight {Failure : Type}
    (prepared source admitted : Except Failure Unit) : Except Failure Unit :=
  match (do prepared; admitted) with
  | .ok () => source
  | .error refused =>
    match candidateReturnInOrder prepared source admitted with
    | .ok () => .error refused
    | .error original => .error original

theorem candidate_return_union_preserves_first_refusal {Failure : Type}
    (prepared source admitted : Except Failure Unit) :
    candidateReturnWithPreflight prepared source admitted =
      candidateReturnInOrder prepared source admitted := by
  cases prepared with
  | error => rfl
  | ok value =>
    cases value
    cases source with
    | error => cases admitted <;> rfl
    | ok value => cases value; cases admitted <;> rfl

theorem candidate_return_cannot_report_admission_before_source :
    (do (.error "stale admission" : Except String Unit)
        (.error "changed source" : Except String Unit)) ≠
      candidateReturnInOrder (.ok ()) (.error "changed source")
        (.error "stale admission") := by
  intro same
  exact (by decide : "stale admission" ≠ "changed source") (Except.error.inj same)

-- If input changed before fallback, its successful recheck never approves
-- the original speculative refusal.
theorem candidate_return_retry_cannot_grant_success {Failure : Type} (refused : Failure) :
    (match (.ok () : Except Failure Unit) with
     | .ok () => .error refused
     | .error original => .error original) = (.error refused : Except Failure Unit) := rfl

theorem candidate_return_checks_after_checkpoint {Failure : Type} (stale : Failure) :
    replayCheckpoint (.ok ()) (.ok ()) (.error stale : Except Failure Unit) =
      .error stale := rfl

-- Forwarding uses exactly the ordered native traversal, not its set of
-- receivers or a list of reconstructed records. Earlier captures keep their
-- position and multiplicity.
def forwardAuthoringReads {Read Failure : Type}
    (earlier nativeTraversal : List Read) (preflight postflight : Except Failure Unit) :
    Except Failure (List Read) := do
  preflight
  postflight
  pure (earlier ++ nativeTraversal)

def deliverAuthoringReads {Read Failure : Type}
    (earlier nativeTraversal : List Read)
    (preflight perDelivery postflight : Except Failure Unit) :
    Except Failure (List Read) := do
  preflight
  perDelivery
  postflight
  pure (earlier ++ nativeTraversal)

theorem forwardAuthoringReads_preserves_order
    {Read Failure : Type} (earlier traversal : List Read)
    (preflight postflight : Except Failure Unit) :
    deliverAuthoringReads earlier traversal preflight (.ok ()) postflight =
      forwardAuthoringReads earlier traversal preflight postflight := by
  cases preflight <;> rfl

-- A legitimate monotone runtime revision that still matches the issued
-- generation at return did not cross that generation during the interval.
theorem no_intermediate_revision_change
    (issued entry during exitRevision : Nat) (atEntry : entry = issued)
    (entryDuring : entry ≤ during) (duringReturn : during ≤ exitRevision)
    (atReturn : exitRevision = issued) : during = issued := by omega

-- Exact endpoint validation by itself does not rule out a raw mutation which
-- is restored before return. An open delivery must keep its own checks.
theorem transient_delivery_refusal_requires_original_path :
    deliverAuthoringReads ([] : List Nat) [1] (.ok ())
      (.error "changed while delivering") (.ok ()) ≠
    forwardAuthoringReads [] [1] (.ok ()) (.ok ()) := by
  intro same
  cases same
-- Lexical evidence fields capture reference identities. Their former
-- receiver-taking bodies ignored the receiver and returned those same values.
def receiptValueSlot {Receiver Value : Type} (value : Value) : Receiver → Value :=
  fun _ => value

theorem lexical_receipt_slot_preserves_reference {Receiver Value : Type}
    (value : Value) (original derived : Receiver) :
    receiptValueSlot value original = receiptValueSlot value derived := rfl

-- Contract identity is a separately demanded live read and may refuse.
-- Constructing or reading lexical fields cannot execute it.
def receiptFields {World Value Identity Failure : Type}
    (value : Value) (identity : World → Except Failure Identity) :=
  (value, identity)

theorem lexical_receipt_fields_do_not_fix_contract_identity
    {World Value Identity Failure : Type}
    (value : Value) (identity : World → Except Failure Identity) (world : World) :
    (receiptFields value identity).2 world = identity world := rfl

-- Each row still owns its original receiver and the suffix read by its body.
-- Sharing immutable method support cannot combine the row-local captures.
def stockDatumTraces (support : List Read) (rows : List (Except Failure (List Read))) :
    List (Except Failure (List Read)) :=
  rows.map (fun row => row.map (support ++ ·))

theorem closed_stock_run_preserves_ordered_owner_traces
    (check : Except Failure Unit) (support : List Read)
    (rows : List (Except Failure (List Read))) :
    checkStockRun check (stockDatumTraces support rows) =
      checkStockEach check (stockDatumTraces support rows) :=
  unchanged_stock_support_preserves_results_and_refusal check _

theorem stock_datum_trace_preserves_owner_suffix (support : List Read)
    (first second : List Read) :
    stockDatumTraces (Failure := Failure) support [.ok first, .ok second] =
      [.ok (support ++ first), .ok (support ++ second)] := rfl

-- The native protected action disables the outer recorder. Publish its
-- original read identities only after its independent return authentication.
def returnStockTrace (entry exit : Except Failure Unit)
    (captured : Except Failure (List Read)) : Except Failure (List Read) := do
  entry
  let trace ← captured
  exit
  pure trace

theorem stale_stock_return_cannot_deliver (stale : Failure) (trace : List Read) :
    returnStockTrace (.ok ()) (.error stale) (.ok trace) = .error stale := rfl

theorem stock_body_refusal_precedes_return_refusal (body stale : Failure) :
    returnStockTrace (.ok ()) (.error stale) (.error body) =
      (.error body : Except Failure (List Nat)) := rfl

-- A role getter or a diagnostic Type is an effect if it runs author code.
-- Authentication of the previous pure segment grants no later permission.
theorem closed_stock_trace_cannot_cross_changed_owner :
    stockAroundOpen checkStockRun
      (fun changed => if changed then .error "stale owner" else .ok ())
      (fun (_ : Bool) => true)
      (fun _ => stockDatumTraces [0] [.ok [1]])
      (fun _ => stockDatumTraces [0] [.ok [2]]) false =
        (.error "stale owner" : Except String (List (List Nat) × List (List Nat) × Bool)) := rfl

-- A role-local trace is structure, not a retained validation result. Each
-- datum separately authenticates the actual current entry and return state.
def dispatchWithOriginalTrace (entry : Except Failure Unit)
    (selected : Except Failure Method) (exit : Except Failure Unit)
    (original : List Read) : Except Failure (Method × List Read) := do
  entry
  let method ← selected
  exit
  pure (method, original)

theorem transparent_dispatch_keeps_fresh_authentication
    (entry exit : Except Failure Unit) (selected : Except Failure Method)
    (captured native : List Read) (same : captured = native) :
    dispatchWithOriginalTrace entry selected exit captured =
      dispatchWithOriginalTrace entry selected exit native := by
  cases same
  rfl

theorem dispatch_reuse_refuses_changed_return
    (method : Method) (captured : List Read) (stale : Failure) :
    dispatchWithOriginalTrace (.ok ()) (.ok method) (.error stale) captured =
      .error stale := rfl

def dispatchWithPerDeliveryAuth (entry delivery exit : Except Failure Unit)
    (selected : Except Failure Method) (original : List Read) :
    Except Failure (Method × List Read) := do
  entry
  let method ← selected
  delivery
  exit
  pure (method, original)

-- Only dispatch metadata is inside the protected region. The equality
-- premise forbids any supported change between entry and silent delivery.
theorem unchanged_dispatch_delivery_auth_is_redundant
    (entry delivery exit : Except Failure Unit)
    (selected : Except Failure Method) (original : List Read)
    (unchanged : delivery = entry) :
    dispatchWithPerDeliveryAuth entry delivery exit selected original =
      dispatchWithOriginalTrace entry selected exit original := by
  subst delivery
  cases entry <;> cases selected <;> rfl

/-- Gerbil resolves a wrapper name through its local bindings, explicit
imports, then its weak prelude. The key includes the expansion phase. -/
def wrapperBinding {Key Binding : Type}
    (localBinding explicit prelude : Key → Option Binding) (key : Key) : Option Binding :=
  (localBinding key).orElse fun _ => (explicit key).orElse fun _ => prelude key

theorem shared_wrapper_bindings_preserve_resolution
    (localBinding explicit prelude sharedPrelude : Key → Option Binding)
    (used : List Key)
    (exact : ∀ key ∈ used, (explicit key).orElse (fun _ => prelude key) = sharedPrelude key) :
    used.map (wrapperBinding localBinding explicit prelude) =
      used.map (wrapperBinding localBinding (fun _ => none) sharedPrelude) := by
  apply List.map_congr_left
  intro key member
  unfold wrapperBinding
  rw [show ((fun _ : Key => none) key : Option Binding).orElse
    (fun _ => sharedPrelude key) = sharedPrelude key from rfl]
  rw [exact key member]

-- A phase-zero match alone is insufficient, even for a single identifier.
theorem same_phase_zero_binding_can_hide_phase_one_change :
    ([0, 1] : List Nat).map (wrapperBinding (fun _ => none)
      (fun _ => some 2) (fun _ => none)) ≠
    [0, 1].map (wrapperBinding (fun _ => none) (fun _ => none)
      (fun phase => if phase = 0 then some 2 else some 3)) := by decide

-- An explicit author import can beat a weak prelude. Closed classification
-- must establish the actual binding route before changing wrapper assembly.
theorem weak_prelude_cannot_override_explicit_import :
    wrapperBinding (Key := Nat) (fun _ => none) (fun _ => some 3) (fun _ => some 2) 0 =
      some 3 := rfl

-- Binding equivalence is separate from native import custody. Moving an
-- import into a shared prelude can leave the name intact while removing the
-- original per-owner edge, which an import guard can observe.
theorem same_wrapper_binding_does_not_preserve_owner_import :
    wrapperBinding (Key := Nat) (fun _ => none) (fun _ => some 2) (fun _ => none) 0 =
      wrapperBinding (Key := Nat) (fun _ => none) (fun _ => none) (fun _ => some 2) 0 ∧
    ([2] : List Nat) ≠ [] := by decide

/-- Cleanup of an exact native registry alias compares the installed Context.
The caller must separately establish that the alias is private and no longer
demanded. Key spelling alone does not establish that ownership. -/
def retireWrapperAlias [DecidableEq Key] [DecidableEq Context]
    (registry : Key → Option Context) (ownedKey : Key) (ownedContext : Context) :
    Key → Option Context :=
  fun key => if key = ownedKey ∧ registry key = some ownedContext then none else registry key

theorem retire_wrapper_alias_preserves_other_bindings
    [DecidableEq Key] [DecidableEq Context]
    (registry : Key → Option Context) (ownedKey key : Key) (ownedContext : Context)
    (other : key ≠ ownedKey) :
    retireWrapperAlias registry ownedKey ownedContext key = registry key := by
  simp [retireWrapperAlias, other]

theorem retire_wrapper_alias_preserves_replacement
    [DecidableEq Key] [DecidableEq Context]
    (registry : Key → Option Context) (key : Key) (ownedContext : Context)
    (replacement : registry key ≠ some ownedContext) :
    retireWrapperAlias registry key ownedContext key = registry key := by
  simp [retireWrapperAlias, replacement]

theorem retiring_a_live_wrapper_alias_changes_resolution :
    retireWrapperAlias (fun _ : Nat => some (5 : Nat)) 2 5 2 ≠ some 5 := by decide

/-- A fixed dispatch may retain native read identities and receiver topology.
Each actual owner still has its own selection and independent authentication. -/
theorem fixed_dispatch_trace_keeps_owner_and_refusal
    (entry exit : Except Failure Unit) (ownerSelection : Except Failure Method)
    (fixed observed : List Read) (sameNativeTrace : fixed = observed) :
    dispatchWithOriginalTrace entry ownerSelection exit fixed =
      dispatchWithOriginalTrace entry ownerSelection exit observed :=
  transparent_dispatch_keeps_fresh_authentication entry exit ownerSelection fixed observed sameNativeTrace

theorem dispatch_receiver_membership_suffices [BEq Receiver] [LawfulBEq Receiver]
    (receivers : List Receiver) (live : Receiver → Bool) :
    receivers.eraseDups.all live = receivers.all live := by
  apply Bool.eq_iff_iff.mpr
  simp [List.all_eq_true]

theorem fixed_trace_still_refuses_at_an_independent_effect
    (fixed : List Read) (oldOwner : Method) (failure : Failure) :
    dispatchWithOriginalTrace (.ok ()) (.ok oldOwner) (.error failure) fixed =
      .error failure := rfl

/-- A single callback-free native pass can share its route for a run of
records with the same live receiver and storage. Prefix checks (issuance
and key) and suffix checks (slot state) remain ordered for every record. -/
def checkReadRoutes {Failure : Type} (route : Except Failure Unit) :
    List (Except Failure Unit × Except Failure Unit) → Except Failure Unit
  | [] => .ok ()
  | (before, slot) :: rest => do
      before
      route
      slot
      checkReadRoutes route rest

def checkSharedReadRoute {Failure : Type} (route : Except Failure Unit) :
    List (Except Failure Unit × Except Failure Unit) → Except Failure Unit
  | [] => .ok ()
  | (before, slot) :: rest => do
      before
      route
      slot
      checkReadRoutes (.ok ()) rest

theorem same_route_run_preserves_first_refusal (route : Except Failure Unit)
    (records : List (Except Failure Unit × Except Failure Unit)) :
    checkSharedReadRoute route records = checkReadRoutes route records := by
  cases records with
  | nil => rfl
  | cons record rest =>
    rcases record with ⟨before, slot⟩
    cases route with
    | ok value => cases value; rfl
    | error cause => cases before <;> rfl

theorem shared_route_keeps_later_slot_refusal (stale : Failure) :
    checkSharedReadRoute (.ok ()) [(.ok (), .ok ()), (.ok (), .error stale)] =
      .error stale := rfl

theorem shared_route_refuses_after_independent_effect (stale : Failure) :
    (do
      checkSharedReadRoute (.ok ()) [(.ok (), .ok ())]
      checkSharedReadRoute (.error stale) [(.ok (), .ok ())]) = .error stale := rfl

-- Equal receiver identities cannot supply the stability premise. In
-- particular, a foreign storage route can refuse the second signed read.
theorem receiver_identity_alone_does_not_authorize_route_reuse :
    checkSharedReadRoute (.ok ()) [(.ok (), .ok ()), (.ok (), .ok ())] ≠
      (do
        checkReadRoutes (.ok ()) [(.ok (), .ok ())]
        checkReadRoutes (.error "changed storage route") [(.ok (), .ok ())]) := by
  change (Except.ok () : Except String Unit) ≠ .error "changed storage route"
  intro impossible
  cases impossible

/-- Capture only source obligations from inert preparation. The effectful
world is supplied anew at each checkpoint, including negative file inputs. -/
def checkSourceRows (check : Path → Option Bytes → Except Failure Unit) :
    List (Path × Option Bytes) → Except Failure Unit
  | [] => .ok ()
  | (path, expected) :: rest => do
      check path expected
      checkSourceRows check rest

theorem prepared_role_rows_preserve_first_refusal
    (roles : List Role) (path : Role → Path) (expected : Path → Option Bytes)
    (check : Path → Option Bytes → Except Failure Unit) :
    checkSourceRows check (roles.map fun role => (path role, expected (path role))) =
      checkSourceRows (fun role _ => check (path role) (expected (path role)))
        (roles.map fun role => (role, (none : Option Bytes))) := by
  induction roles with
  | nil => rfl
  | cons role rest ih => simp only [List.map_cons, checkSourceRows, ih]

theorem prepared_absence_is_checked_again (stale : Failure) :
    checkSourceRows (fun (_ : Nat) (_ : Option Unit) => .error stale)
      [(0, none)] = .error stale := rfl

-- An observer may change the path of a later role while the guard is active.
-- Rechecking the original path cannot establish the required live path.
theorem retargeted_role_cannot_reuse_prepared_path :
    checkSourceRows (fun path (_ : Option Unit) =>
      if path = (0 : Nat) then .ok () else .error "stale role path") [(0, none)] ≠
    checkSourceRows (fun path (_ : Option Unit) =>
      if path = (0 : Nat) then .ok () else .error "stale role path") [(1, none)] := by
  change (Except.ok () : Except String Unit) ≠ .error "stale role path"
  intro impossible
  cases impossible

/-- A closed literal has no receiver reads. Lowering it to a native constant
specification preserves the value for each owner; other slot bodies keep
their original receiver and observation sequence. -/
def frameSlot (literal : Option Value) (body : Owner → Value × List Read)
    (owner : Owner) : Value × List Read :=
  match literal with
  | some value => (value, [])
  | none => body owner

theorem closed_literal_slot_preserves_owner_read
    (literal : Option Value) (body : Owner → Value × List Read)
    (exact : ∀ value, literal = some value → ∀ owner, body owner = (value, []))
    (owner : Owner) : frameSlot literal body owner = body owner := by
  cases literal with
  | none => rfl
  | some value => exact (exact value rfl owner).symm

theorem owner_dependent_slot_cannot_share_a_literal :
    frameSlot (some 0) (fun (owner : Nat) => (owner, ([] : List Unit))) 1 ≠
      (1, []) := by decide

theorem frame_environment_survives_either_slot
    (deps : Node → List Node) (roots : List Node) (core features environment : Node)
    (coreCapture : environment ∈ deps core) (featureCapture : environment ∈ deps features)
    (retained : core ∈ roots ∨ features ∈ roots) :
    Demanded deps roots environment := by
  rcases retained with coreRoot | featureRoot
  · exact Demanded.dependency core environment (Demanded.root core coreRoot) coreCapture
  · exact Demanded.dependency features environment (Demanded.root features featureRoot) featureCapture

/-- The private wrapper captures the resolver when it creates the owner.
The native slot calls the same deferred body on that owner and resolver. -/
def privateCoreSlot (body : Owner → Resolver → Except Failure Result)
    (captured : Resolver) : Owner → Except Failure Result :=
  fun owner => body owner captured

theorem private_core_slot_preserves_owner_and_resolver
    (body : Owner → Resolver → Except Failure Result)
    (captured : Resolver) (owner : Owner) :
    privateCoreSlot body captured owner = body owner captured := rfl

theorem private_core_slot_keeps_independent_effect_refusal
    (captured : Resolver) (owner : Owner) (entry : Except Failure Unit)
    (run : Owner → Resolver → Except Failure Result) (after : Result → Except Failure Unit) :
    (do
      entry
      let result ← privateCoreSlot run captured owner
      after result
      pure result) =
    (do
      entry
      let result ← run owner captured
      after result
      pure result) := rfl

theorem later_ambient_resolver_cannot_replace_owner_capture :
    privateCoreSlot (fun (_ : Unit) (resolver : Nat) => (Except.ok resolver : Except Unit Nat))
      0 () ≠ .ok 1 := by
  intro same
  cases same

-- A stock expansion can share the operations after Gerbil has resolved the
-- lexical references. These are distinct native reads even when their names
-- coincide. The recipe contains neither a receiver nor an admission verdict.
inductive StockInterfaceRead (Name : Type) where
  | roleReceiver
  | roleAlias (name : Name)
  | dependency (name : Name)

def ownerStockReads (recipe : List (StockInterfaceRead Name))
    (read : Owner → Resolver → StockInterfaceRead Name → Except Failure Value)
    (owner : Owner) (resolver : Resolver) : Except Failure (List Value) :=
  recipe.mapM (read owner resolver)

-- The owner wrapper previously emitted one closure per lexical read. A
-- shared recipe binds the same operands at invocation, in the same order.
-- The list describes one demanded computation, never all deferred slots.
theorem shared_stock_reads_preserve_owner_and_first_refusal
    (recipe : List (StockInterfaceRead Name))
    (read : Owner → Resolver → StockInterfaceRead Name → Except Failure Value)
    (owner : Owner) (resolver : Resolver) :
    ((recipe.map (fun op => fun () => read owner resolver op)).mapM fun run => run ()) =
      ownerStockReads recipe read owner resolver := by
  simp [ownerStockReads, List.mapM_map, Function.comp_def]

theorem shared_stock_reads_do_not_reuse_another_resolver :
    let recipe := [StockInterfaceRead.roleAlias (Name := Nat) 0]
    let read (owner resolver : Nat) (_ : StockInterfaceRead Nat) : Except String Nat :=
      .ok (owner + resolver)
    ownerStockReads recipe read 1 2 ≠ ownerStockReads recipe read 1 3 := by
  dsimp only
  intro same
  change (Except.ok [3] = (Except.ok [4] : Except String (List Nat))) at same
  cases same

/-- Keep the independent checks after Gerbil expansion and after the author
callback. Each takes the live state from its own effect boundary. -/
def deliverStockInterface (entry : Except Failure Unit)
    (expand : Except Failure (State × List (StockInterfaceRead Name)))
    (check : State → Except Failure Unit)
    (author : List Value → State → Except Failure (Result × State))
    (read : Owner → Resolver → StockInterfaceRead Name → Except Failure Value)
    (owner : Owner) (resolver : Resolver) : Except Failure Result := do
  entry
  let (expanded, recipe) ← expand
  check expanded
  let bindings ← ownerStockReads recipe read owner resolver
  let (result, afterAuthor) ← author bindings expanded
  check afterAuthor
  pure result

theorem shared_stock_interface_refuses_mutation_at_each_effect :
    let check (current : Bool) : Except String Unit :=
      if current then .ok () else .error "stale owner"
    let read (_owner _resolver : Unit) (_ : StockInterfaceRead Nat) : Except String Unit :=
      .ok ()
    let run (expanded : Bool) (author : List Unit → Bool → Except String (Unit × Bool)) :=
      deliverStockInterface (.ok ()) (.ok (expanded, [.roleReceiver])) check author read () ()
    run false (fun _ _ => .error "author should not run") = .error "stale owner" ∧
    run true (fun _ _ => .ok ((), false)) = .error "stale owner" := ⟨rfl, rfl⟩

end YuanxuProof.ModuleSystem.Graph.PublicationReads
