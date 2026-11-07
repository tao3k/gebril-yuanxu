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
end YuanxuProof.ModuleSystem.Graph.PublicationReads
