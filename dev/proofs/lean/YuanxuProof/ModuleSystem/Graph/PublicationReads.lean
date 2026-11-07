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

-- Runtime correspondence premises remain: eq?-identity normalization,
-- unmodified original dependency lists, public replay's final recheck,
-- unchanged real observer delivery, and no nonlocal continuation escape.
-- This does not prove SDK ownership, GC behavior or a memory byte bound.
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

end YuanxuProof.ModuleSystem.Graph.PublicationReads
