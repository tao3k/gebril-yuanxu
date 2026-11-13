-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission
import YuanxuProof.ModuleSystem.Loading.IncrementalRoles
import YuanxuProof.ModuleSystem.Loading.DependencyPublication

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

-- A warm replay currently checks every birth before starting live state
-- checks. Try the two tests together on the same ordered records. Failure
-- must run the original split checks to recover its refusal precedence.
def splitReplayEntry (issued live : Read → Except Failure Unit) (reads : List Read) :
    Except Failure Unit := do
  authenticateAndVisit issued (fun _ => ()) reads
  authenticateAndVisit live (fun _ => ()) reads

def fusedReplayEntry (issued live : Read → Except Failure Unit) (reads : List Read) :
    Except Failure Unit :=
  match authenticateAndVisit (fun read => do issued read; live read) (fun _ => ()) reads with
  | .ok () => .ok ()
  | .error _ => splitReplayEntry issued live reads

theorem fused_entry_success_covers_both_checks
    (issued live : Read → Except Failure Unit) (reads : List Read)
    (passed : authenticateAndVisit
      (fun read => do issued read; live read) (fun _ => ()) reads = .ok ()) :
    splitReplayEntry issued live reads = .ok () := by
  induction reads with
  | nil => rfl
  | cons read rest ih =>
    cases issuedHere : issued read with
    | error failure => simp [authenticateAndVisit, issuedHere, Except.bind, bind] at passed
    | ok issuedUnit =>
      cases issuedUnit
      cases liveHere : live read with
      | error failure => simp [authenticateAndVisit, issuedHere, liveHere, Except.bind, bind] at passed
      | ok liveUnit =>
        cases liveUnit
        have tail := ih (by simpa [authenticateAndVisit, issuedHere, liveHere, Except.bind, bind] using passed)
        simpa [splitReplayEntry, authenticateAndVisit, issuedHere, liveHere, Except.bind, bind] using tail

theorem fused_entry_preserves_split_refusal
    (issued live : Read → Except Failure Unit) (reads : List Read) :
    fusedReplayEntry issued live reads = splitReplayEntry issued live reads := by
  unfold fusedReplayEntry
  split
  next passed => exact (fused_entry_success_covers_both_checks issued live reads passed).symm
  next => rfl

theorem split_entry_second_issuance_reads_same_state
    (issued live : Read → Except Failure Unit) (reads : List Read) :
    splitReplayEntry issued (fun read => do issued read; live read) reads =
      splitReplayEntry issued live reads := by
  have noRepeat : ∀ rows : List Read, authenticateAndVisit issued (fun _ => ()) rows = .ok () →
      authenticateAndVisit (fun read => do issued read; live read) (fun _ => ()) rows =
        authenticateAndVisit live (fun _ => ()) rows := by
    intro rows passed
    induction rows with
    | nil => rfl
    | cons read rest ih =>
      cases issuedHere : issued read with
      | error failure => simp [authenticateAndVisit, issuedHere, Except.bind, bind] at passed
      | ok checked =>
        cases checked
        have tail := ih (by simpa [authenticateAndVisit, issuedHere, Except.bind, bind] using passed)
        cases liveHere : live read <;>
          simp [authenticateAndVisit, issuedHere, liveHere, Except.bind, bind] <;> exact tail
  unfold splitReplayEntry
  cases entered : authenticateAndVisit issued (fun _ => ()) reads with
  | error failure => rfl
  | ok checked =>
    cases checked
    exact noRepeat reads entered

theorem fused_entry_keeps_independent_return
    (issued live after : Read → Except Failure Unit) (reads : List Read) :
    (do fusedReplayEntry issued live reads; authenticateAndVisit after (fun _ => ()) reads) =
    (do splitReplayEntry issued (fun read => do issued read; live read) reads
        authenticateAndVisit after (fun _ => ()) reads) := by
  rw [fused_entry_preserves_split_refusal, split_entry_second_issuance_reads_same_state]

/-- Route key shape is signed structure. A projected shape can replace the
runtime key grammar check only after the current issuance check. Live state
and the first-refusal order still belong to the current sweep. -/
theorem authenticated_key_shape_preserves_sweep
    (issued grammar projected live : Read → Except Failure Unit) (reads : List Read)
    (signedShape : ∀ read, issued read = .ok () → projected read = grammar read) :
    authenticateAndVisit (fun read => do issued read; projected read; live read)
      (fun _ => ()) reads =
    authenticateAndVisit (fun read => do issued read; grammar read; live read)
      (fun _ => ()) reads := by
  have same : (fun read => do issued read; projected read; live read) =
      (fun read => do issued read; grammar read; live read) := by
    funext read
    cases checked : issued read with
    | error failure => rfl
    | ok result =>
      cases result
      simp [signedShape read checked]
  rw [same]

-- A retry determines the original diagnostic precedence. A concurrent
-- restoration during that retry cannot erase the already observed refusal.
def diagnosticEntryRetry (first : Failure) (split : Except Failure Unit) :
    Except Failure Unit :=
  match split with
  | .ok () => .error first
  | .error cause => .error cause

theorem diagnostic_retry_cannot_approve
    (first : Failure) (split : Except Failure Unit) :
    ∃ cause, diagnosticEntryRetry first split = .error cause := by
  cases split with
  | error cause => exact ⟨cause, rfl⟩
  | ok checked =>
    cases checked
    exact ⟨first, rfl⟩

-- The native topology lookup authenticates issuance in its own original
-- preorder. A validation-only checkpoint can use one live pass if both
-- passes see the same state and the intervening action has no effect.
def validateOnlyCheckpoint
    (issuance entry exit : Read → Except Failure Unit) (reads : List Read) :
    Except Failure Unit := do
  authenticateAndVisit issuance (fun _ => ()) reads
  readWindow entry exit (fun _ => ()) reads (.ok ())

def validateOnlyAtExit
    (issuance exit : Read → Except Failure Unit) (reads : List Read) :
    Except Failure Unit := do
  authenticateAndVisit issuance (fun _ => ()) reads
  authenticateAndVisit exit (fun _ => ()) reads

theorem validation_only_same_state_needs_one_live_pass
    (issuance entry exit : Read → Except Failure Unit) (reads : List Read)
    (stable : ∀ read ∈ reads, entry read = exit read) :
    validateOnlyCheckpoint issuance entry exit reads =
    validateOnlyAtExit issuance exit reads := by
  have live : authenticateAndVisit entry (fun _ => ()) reads =
      authenticateAndVisit exit (fun _ => ()) reads := by
    induction reads with
    | nil => rfl
    | cons read rest ih =>
      simp only [authenticateAndVisit, stable read (by simp)]
      rw [ih (fun next member => stable next (by simp [member]))]
  unfold validateOnlyCheckpoint validateOnlyAtExit readWindow
  rw [live]
  cases authenticateAndVisit issuance (fun _ => ()) reads <;>
    cases authenticateAndVisit exit (fun _ => ()) reads <;> rfl

theorem exit_only_can_lose_earlier_refusal (read : Read) (refused : Failure) :
    validateOnlyCheckpoint (fun _ => .ok ()) (fun _ => .error refused)
      (fun _ => .ok ()) [read] = .error refused ∧
    validateOnlyAtExit (Failure := Failure) (fun _ => .ok ()) (fun _ => .ok ()) [read] = .ok () :=
  ⟨rfl, rfl⟩

-- A one-pass check on a mutable runtime needs a common point of validity.
-- Under permanent invalidation, a record that is still current when visited
-- was current at the beginning of the scan. The proof requires the premise
-- for every record, including structural routes and issuance, not just POO
-- receiver revisions.
theorem monotone_live_scan_has_common_entry
    (live : Read → Nat → Prop) (visited : List (Read × Nat)) (entry : Nat)
    (permanent : ∀ read earlier later, earlier ≤ later → live read later → live read earlier)
    (checked : ∀ item ∈ visited, entry ≤ item.2 ∧ live item.1 item.2) :
    ∀ item ∈ visited, live item.1 entry := by
  intro item member
  exact permanent _ _ _ (checked item member).1 (checked item member).2

-- A compiler inventory visits a native Context together with the origin
-- already stored for it. Point lookup and traversal have the same inputs
-- while that table is fixed. Read the actual Context again in both lanes.
theorem compiler_inventory_rows_preserve_refusal
    {Context Origin Failure : Type} (rows : List (Context × Origin))
    (lookup : Context → Option Origin)
    (current : Context → Option Origin → Except Failure Unit)
    (exactEntry : ∀ row ∈ rows, lookup row.1 = some row.2) :
    authenticateAndVisit (fun row => current row.1 (lookup row.1)) (fun _ => ()) rows =
    authenticateAndVisit (fun row => current row.1 (some row.2)) (fun _ => ()) rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    simp only [authenticateAndVisit, exactEntry row (by simp)]
    rw [ih (fun other member => exactEntry other (by simp [member]))]

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

-- A successful private Profile result still needs its actual child value
-- decisions, including preservation of each supplied role's identity. The
-- public path keeps its detailed refusal when any stock premise fails.
structure ProfileRoleCheck (Value : Type) where
  supplied : Value
  normalized : Value
  classified : Bool
  evidenceAdmitted : Bool

def profileRoleValueAccepted [BEq Value] (role : ProfileRoleCheck Value) : Bool :=
  (role.normalized == role.supplied) && role.classified

def profileRoleAccepted [BEq Value] (role : ProfileRoleCheck Value) : Bool :=
  profileRoleValueAccepted role && role.evidenceAdmitted

def checkedProfileValue [BEq Value] (profile : Value) (root : Bool)
    (roles : List (ProfileRoleCheck Value)) (rootEvidence : Bool)
    (refusal : Failure) : Except Failure Value :=
  if root && roles.all profileRoleAccepted && rootEvidence then .ok profile
  else .error refusal

-- The caller may select this lane only with actual stock producer custody.
-- A failed structural check stays with the full original refusal path.
def projectedProfileValue [BEq Value] (owned : Bool) (profile : Value) (root : Bool)
    (roles : List (ProfileRoleCheck Value)) (rootEvidence : Bool)
    (refusal : Failure) : Except Failure Value :=
  if owned && root && roles.all profileRoleValueAccepted then .ok profile
  else checkedProfileValue profile root roles rootEvidence refusal

theorem projected_stock_profile_preserves_value_and_refusal [BEq Value]
    (owned : Bool) (profile : Value) (root : Bool) (roles : List (ProfileRoleCheck Value))
    (rootEvidence : Bool) (refusal : Failure)
    (receiptSupport : owned = true → root = true → roles.all profileRoleValueAccepted = true →
      rootEvidence = true ∧ ∀ role ∈ roles, role.evidenceAdmitted = true) :
    projectedProfileValue owned profile root roles rootEvidence refusal =
      checkedProfileValue profile root roles rootEvidence refusal := by
  cases owned <;> cases root <;> simp [projectedProfileValue]
  case true.true =>
    by_cases accepted : roles.all profileRoleValueAccepted = true
    · have support := receiptSupport rfl rfl accepted
      have allAdmitted : roles.all profileRoleAccepted = true := by
        apply List.all_eq_true.mpr
        intro role member
        simp [profileRoleAccepted, List.all_eq_true.mp accepted role member, support.2 role member]
      simp [checkedProfileValue, allAdmitted, support.1]
    · intro allRoles
      exact False.elim (accepted (List.all_eq_true.mpr allRoles))

theorem unchanged_role_value_can_have_rejected_evidence :
    profileRoleValueAccepted (⟨(0 : Nat), 0, true, false⟩ : ProfileRoleCheck Nat) = true ∧
    profileRoleAccepted (⟨(0 : Nat), 0, true, false⟩ : ProfileRoleCheck Nat) = false :=
  ⟨rfl, rfl⟩

-- Resolve the actual method once. A replacement receives the receipt only
-- after the existing open boundary has authenticated its entry.
def resolvedEvidenceCall (maintained : Bool) (boundary : Except Failure Unit)
    (invoke : Except Failure Result) : Except Failure Result :=
  if maintained then invoke else do
    boundary
    invoke

theorem maintained_evidence_method_preserves_result
    (boundary : Except Failure Unit) (invoke : Except Failure Result) :
    resolvedEvidenceCall true boundary invoke = invoke := rfl

theorem replacement_evidence_method_cannot_outrun_refusal
    (refusal : Failure) (invoke : Except Failure Result) :
    resolvedEvidenceCall false (.error refusal) invoke = .error refusal := rfl

theorem replacement_evidence_method_keeps_selected_result
    (invoke : Except Failure Result) :
    resolvedEvidenceCall false (.ok ()) invoke = invoke := by
  cases invoke <;> rfl

-- A Record can resolve the nested classification Type directly. An effect
-- check belongs to delivery of that actual method read, after earlier fields
-- have passed and before the chosen method can receive the receipt.
def checkNestedEvidence (earlierFields : Except Failure Bool)
    (resolve : Except Failure Bool) (boundary : Except Failure Unit)
    (invoke : Except Failure Bool) : Except Failure Bool := do
  if ← earlierFields then
    let maintained ← resolve
    resolvedEvidenceCall maintained boundary invoke
  else pure false

theorem rejected_record_prefix_never_checks_nested_effect
    (resolve : Except Failure Bool) (boundary : Except Failure Unit)
    (invoke : Except Failure Bool) :
    checkNestedEvidence (.ok false) resolve boundary invoke = .ok false := rfl

theorem nested_resolution_refusal_precedes_effect
    (refusal : Failure) (boundary : Except Failure Unit) (invoke : Except Failure Bool) :
    checkNestedEvidence (.ok true) (.error refusal) boundary invoke = .error refusal := rfl

theorem replaced_nested_evidence_cannot_outrun_refusal
    (refusal : Failure) (invoke : Except Failure Bool) :
    checkNestedEvidence (.ok true) (.ok false) (.error refusal) invoke = .error refusal := rfl

theorem maintained_nested_evidence_preserves_result
    (boundary : Except Failure Unit) (invoke : Except Failure Bool) :
    checkNestedEvidence (.ok true) (.ok true) boundary invoke = invoke := rfl

theorem replaced_slot_method_cannot_expose_evidence
    (refusal : Failure) (slotCheck resolve invoke : Except Failure Bool)
    (boundary : Except Failure Unit) :
    checkNestedEvidence (resolvedEvidenceCall false (.error refusal) slotCheck)
      resolve boundary invoke = .error refusal := rfl

-- The native copy extends the ordered direct-slot map. A stock evidence
-- constructor can supply the final field at allocation when the field is
-- fresh and neither constructor invocation can expose the intermediate.
def extendReceiptSlots {Key Value : Type} [DecidableEq Key]
    (slots : List (Key × Value)) (key : Key) (value : Value) : List (Key × Value) :=
  match slots with
  | [] => [(key, value)]
  | first :: rest =>
    if first.1 = key then (key, value) :: rest
    else first :: extendReceiptSlots rest key value

theorem fresh_receipt_field_preserves_order {Key Value : Type} [DecidableEq Key]
    (slots : List (Key × Value)) (key : Key) (value : Value)
    (fresh : key ∉ slots.map Prod.fst) :
    extendReceiptSlots slots key value = slots ++ [(key, value)] := by
  induction slots with
  | nil => rfl
  | cons first rest ih =>
    simp only [List.map_cons, List.mem_cons, not_or] at fresh
    simp [extendReceiptSlots, Ne.symm fresh.1, ih fresh.2]

-- The diagnostic width travels with the guard spine. One replacement makes
-- a new head and its count visible together and does not discharge a guard.
def pushSourceGuard {Guard : Type} (guard : Guard) (support : List Guard × Nat) :
    List Guard × Nat :=
  (guard :: support.1, support.2 + 1)

theorem source_guard_push_keeps_count_and_order {Guard : Type} (guards : List Guard) :
    let support := guards.foldl (fun support guard => pushSourceGuard guard support) ([], 0)
    support.1 = guards.reverse ∧ support.2 = guards.length := by
  have general : ∀ (rest spine : List Guard) (width : Nat),
      rest.foldl (fun support guard => pushSourceGuard guard support) (spine, width) =
        (rest.reverse ++ spine, width + rest.length) := by
    intro rest
    induction rest with
    | nil => simp
    | cons guard rest ih =>
      intro spine width
      rw [List.foldl_cons, show pushSourceGuard guard (spine, width) =
        (guard :: spine, width + 1) from rfl, ih]
      simp only [List.reverse_cons, List.append_assoc, List.singleton_append, List.length_cons]
      congr 1
      omega
  simp [general]

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

-- A derived scratch receiver can become stale through a retained ancestor
-- without escaping. An omitted refusal is harmless only when an earlier
-- retained check already refuses. Keep the original preorder, including
-- when several independent source or type edits are visible.
def PrefixCovered (auth : Read → Except Failure Unit)
    (keep : Read → Bool) (reads : List Read) : Prop :=
  ∀ earlier read suffix, reads = earlier ++ read :: suffix →
    keep read = false →
    authenticateAndVisit auth (fun _ => ()) (earlier.filter keep) = .ok () →
    auth read = .ok ()

-- Signed dependencies are still traversed when a caller drops a root. The
-- selected order can stand in for roots only when its retained records are
-- closed under those edges in the original traversal.
theorem closed_read_selection_demands_exactly
    (deps : Node → List Node) (order : List Node) (keep : Node → Bool)
    (complete : ∀ parent ∈ order, ∀ child ∈ deps parent, child ∈ order)
    (closed : ∀ parent ∈ order, keep parent = true →
      ∀ child ∈ deps parent, keep child = true)
    (node : Node) :
    Demanded deps (order.filter keep) node ↔ node ∈ order.filter keep := by
  constructor
  · intro demand
    induction demand with
    | root _ member => exact member
    | dependency parent child _ edge ih =>
      obtain ⟨member, kept⟩ := List.mem_filter.mp ih
      exact List.mem_filter.mpr ⟨complete parent member child edge,
        closed parent member kept child edge⟩
  · exact Demanded.root node

theorem filtering_roots_cannot_hide_a_retained_signed_dependency
    (deps : Node → List Node) (order : List Node) (keep : Node → Bool)
    (parent child : Node) (parentPresent : parent ∈ order)
    (retained : keep parent = true) (omitted : keep child = false)
    (edge : child ∈ deps parent) :
    Demanded deps (order.filter keep) child ∧ child ∉ order.filter keep := by
  constructor
  · exact Demanded.dependency parent child
      (Demanded.root parent (List.mem_filter.mpr ⟨parentPresent, retained⟩)) edge
  · simp [omitted]

theorem prefix_guarded_reads_preserve_first_refusal
    (auth : Read → Except Failure Unit) (keep : Read → Bool) (reads : List Read)
    (guarded : PrefixCovered auth keep reads) :
    authenticateAndVisit auth (fun _ => ()) (reads.filter keep) =
      authenticateAndVisit auth (fun _ => ()) reads := by
  induction reads with
  | nil => rfl
  | cons read rest ih =>
    cases kept : keep read with
    | false =>
      have current := guarded [] read rest rfl kept rfl
      have restGuarded : PrefixCovered auth keep rest := by
        intro before next after shape omitted entry
        apply guarded (read :: before) next after (by simp [shape]) omitted
        simpa [kept] using entry
      simp [kept, authenticateAndVisit, current, Except.bind, bind, ih restGuarded]
    | true =>
      cases current : auth read with
      | error refused => simp [kept, authenticateAndVisit, current, Except.bind, bind]
      | ok checked =>
        cases checked
        have restGuarded : PrefixCovered auth keep rest := by
          intro before next after shape omitted entry
          apply guarded (read :: before) next after (by simp [shape]) omitted
          simp [kept, authenticateAndVisit, current, Except.bind, bind, entry]
        simp [kept, authenticateAndVisit, current, Except.bind, bind, ih restGuarded]

theorem projected_prefix_guarded_read_window
    (before after : Read → Except Failure Unit) (keep : Read → Bool)
    (reads : List Read) (action : Except Failure Result)
    (beforeCovered : PrefixCovered before keep reads)
    (afterCovered : PrefixCovered after keep reads) :
    readWindow before after (fun _ => ()) (reads.filter keep) action =
      readWindow before after (fun _ => ()) reads action := by
  simp only [readWindow,
    prefix_guarded_reads_preserve_first_refusal before keep reads beforeCovered,
    prefix_guarded_reads_preserve_first_refusal after keep reads afterCovered]

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

-- A retained native root may expose a descendant after the producer returned.
-- Construction-time custody alone cannot justify skipping its return check.
theorem later_observation_can_invalidate_private_return
    (read : Read) (value : Result) (stale : Failure) :
    readWindow (fun _ => .ok ()) (fun _ => .error stale) (fun _ => ()) [read] (.ok value)
      = .error stale ∧
    readWindow (fun _ => .ok ()) (fun _ => .error stale) (fun _ => ()) ([] : List Read) (.ok value)
      = .ok value := by
  constructor <;> rfl

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

-- Only recorded identity membership is selected here. The projection's
-- live issuer and receiver checks remain in their original order.
theorem bounded_recorded_lookup_preserves_ordered_membership
    (scan indexed : Read → Bool) (queries : List Read) (budget : Nat)
    (exactMembership : ∀ read, indexed read = scan read) :
    (queries.take budget).map scan ++ (queries.drop budget).map indexed =
      queries.map indexed := by
  have scanned : (queries.take budget).map scan = (queries.take budget).map indexed := by
    apply List.map_congr_left
    intro read _
    exact (exactMembership read).symm
  rw [scanned, ← List.map_append, List.take_append_drop]

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

-- A deferred handoff must keep the location, policy and source checks in
-- order even if its two intermediate POO checks can share an entry verdict.
def deferredPreparationChecks {Failure : Type}
    (entry location policy afterLocation entryPolicy entrySource handoff
      inputLocation inputPolicy beforeInputs afterInputs returnPolicy inputSource :
      Except Failure Unit) : Except Failure Unit := do
  replayCheckpoint entry (do location; policy) afterLocation
  entryPolicy
  entrySource
  handoff
  inputLocation
  inputPolicy
  replayCheckpoint beforeInputs (.ok ()) afterInputs
  returnPolicy
  inputSource

def deferredPreparationWindow {Failure : Type}
    (entry location policy entryPolicy entrySource handoff
      inputLocation inputPolicy afterInputs returnPolicy inputSource :
      Except Failure Unit) : Except Failure Unit := do
  replayCheckpoint entry (do
    location
    policy
    entryPolicy
    entrySource
    handoff
    inputLocation
    inputPolicy) afterInputs
  returnPolicy
  inputSource

theorem closed_deferred_preparation_preserves_refusal {Failure : Type}
    (entry location policy afterLocation entryPolicy entrySource handoff
      inputLocation inputPolicy beforeInputs afterInputs returnPolicy inputSource :
      Except Failure Unit)
    (locationStable : afterLocation = entry) (inputStable : beforeInputs = entry) :
    deferredPreparationWindow entry location policy entryPolicy entrySource handoff
      inputLocation inputPolicy afterInputs returnPolicy inputSource =
    deferredPreparationChecks entry location policy afterLocation entryPolicy entrySource handoff
      inputLocation inputPolicy beforeInputs afterInputs returnPolicy inputSource := by
  subst afterLocation
  subst beforeInputs
  cases entry <;> cases location <;> cases policy <;> cases entryPolicy <;>
    cases entrySource <;> cases handoff <;> cases inputLocation <;> cases inputPolicy <;> rfl

-- Even with a current entry, an intervening effect can make the omitted
-- checkpoint own the first refusal before the later source check fails.
theorem deferred_preparation_requires_independent_open_refusal :
    deferredPreparationWindow (.ok ()) (.ok ()) (.ok ()) (.ok ()) (.ok ()) (.ok ())
      (.error "source moved") (.ok ()) (.ok ()) (.ok ()) (.ok ()) ≠
    deferredPreparationChecks (.ok ()) (.ok ()) (.ok ()) (.error "stale slot") (.ok ())
      (.ok ()) (.ok ()) (.error "source moved") (.ok ()) (.ok ()) (.ok ()) (.ok ()) (.ok ()) := by
  intro same
  exact (by decide : "source moved" ≠ "stale slot") (Except.error.inj same)

-- The primitive disables capture as well as observers and prechecks.
-- A callback-free interval can still emit required POO read records.
def deferredHandoffDelivery (protectedWindow : Bool) (demands : List Read) : List Read :=
  if protectedWindow then [] else demands

theorem deferred_handoff_preserves_read_delivery (demands : List Read) :
    deferredHandoffDelivery true demands = deferredHandoffDelivery false demands ↔
    demands = [] := by
  change ([] = demands) ↔ demands = []
  exact eq_comm

-- A native frame can mute its own authentication while leaving the action
-- in the caller's recorder. A refusal on return does not undo prior delivery.
def recordedHandoff {Failure Result : Type} (entry postflight : Except Failure Unit)
    (action : Except Failure Result × List Read) : Except Failure Result × List Read :=
  match entry with
  | .error cause => (.error cause, [])
  | .ok () =>
    ((do
      let value ← action.1
      postflight
      pure value), action.2)

theorem recorded_handoff_refused_entry_delivers_nothing {Failure Result : Type}
    (cause : Failure) (postflight : Except Failure Unit)
    (action : Except Failure Result × List Read) :
    recordedHandoff (.error cause) postflight action = (.error cause, []) := rfl

theorem recorded_handoff_keeps_reads_when_return_refuses {Failure Result : Type}
    (stale : Failure) (value : Result) (reads : List Read) :
    recordedHandoff (.ok ()) (.error stale) (.ok value, reads) =
      (.error stale, reads) := rfl

theorem recorded_handoff_keeps_author_refusal_and_reads {Failure Result : Type}
    (cause : Failure) (postflight : Except Failure Unit) (reads : List Read) :
    recordedHandoff (Result := Result) (.ok ()) postflight (.error cause, reads) =
      (.error cause, reads) := rfl

theorem admitted_handoff_can_mute_action_iff_empty {Failure Result : Type}
    (postflight : Except Failure Unit) (action : Except Failure Result × List Read) :
    recordedHandoff (.ok ()) postflight (action.1, []) =
      recordedHandoff (.ok ()) postflight action ↔ action.2 = [] := by
  constructor
  · intro same
    exact (congrArg Prod.snd same).symm
  · intro empty
    rcases action with ⟨outcome, reads⟩
    change reads = [] at empty
    subst reads
    rfl

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

-- The private role table stores only source texts. Its optional lookup
-- supplies both presence and bytes, while the live path is still resolved
-- independently for every role. No source comparison is retained.
theorem role_text_lookup_preserves_live_check
    {Path Bytes Failure : Type} (path : Path) (expected : Option Bytes)
    (present : Path → Bytes → Except Failure Unit)
    (absent : Path → Except Failure Unit) :
    (if expected.isSome then expected.elim (absent path) (present path) else absent path) =
      expected.elim (absent path) (present path) := by
  cases expected <;> rfl

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


/-- A shared Profile root and owner-local roots can share traversal structure
while requiring currentness for every demanded record at the new cut. -/
theorem demanded_append (deps : α → List α) (shared owner : List α) (node : α) :
    Demanded deps (shared ++ owner) node ↔
      Demanded deps shared node ∨ Demanded deps owner node := by
  constructor
  · intro demand
    induction demand with
    | root node member =>
      cases List.mem_append.mp member with
      | inl left => exact Or.inl (.root node left)
      | inr right => exact Or.inr (.root node right)
    | dependency parent child _ edge ih =>
      cases ih with
      | inl left => exact Or.inl (.dependency parent child left edge)
      | inr right => exact Or.inr (.dependency parent child right edge)
  · intro demand
    cases demand with
    | inl left =>
      induction left with
      | root node member => exact .root node (List.mem_append.mpr (Or.inl member))
      | dependency parent child _ edge ih => exact .dependency parent child ih edge
    | inr right =>
      induction right with
      | root node member => exact .root node (List.mem_append.mpr (Or.inr member))
      | dependency parent child _ edge ih => exact .dependency parent child ih edge

theorem current_append (deps : α → List α) (shared owner : List α) (fresh : α → Prop) :
    Current deps (shared ++ owner) fresh ↔
      Current deps shared fresh ∧ Current deps owner fresh := by
  constructor
  · intro both
    exact ⟨fun node demand => both node ((demanded_append deps shared owner node).mpr (.inl demand)),
           fun node demand => both node ((demanded_append deps shared owner node).mpr (.inr demand))⟩
  · intro ⟨left, right⟩ node demand
    exact ((demanded_append deps shared owner node).mp demand).elim (left node) (right node)

/-- Removing one issued read from its receiver after an effect can leave all
owner-local reads current. Entry approval of the shared Profile cannot be
transported through that effect, even when the roots and edges are identical. -/
theorem shared_profile_recheck_is_independent (deps : α → List α) (shared owner : List α)
    (before after : α → Prop) (lost : α)
    (entry : Current deps (shared ++ owner) before)
    (localAfter : Current deps owner after)
    (sharedRead : Demanded deps shared lost) (removed : ¬ after lost) :
    Current deps shared before ∧ Current deps owner after ∧
      ¬ Current deps (shared ++ owner) after := by
  refine ⟨((current_append deps shared owner before).mp entry).1, localAfter, ?_⟩
  intro both
  exact removed (((current_append deps shared owner after).mp both).1 lost sharedRead)

namespace ScopeProjection

/-- Source-policy facts are shared; owner receipts are selected through the
Module dependency closure. The two dependency relations remain distinct. -/
def ScopeCurrent (modules : Owner → List Owner) (reads : Read → List Read)
    (shared : List Read) (support : Owner → List Read) (selected : List Owner)
    (fresh : Read → Prop) : Prop :=
  Current reads shared fresh ∧
    ∀ owner, Demanded modules selected owner → Current reads (support owner) fresh

def scopeRoots (shared : List Read) (owners : List Owner) (support : Owner → List Read) :
    List Read := shared ++ owners.flatMap support

theorem demanded_owner_roots (reads : Read → List Read) (owners : List Owner)
    (support : Owner → List Read) (read : Read) :
    Demanded reads (owners.flatMap support) read ↔
      ∃ owner, owner ∈ owners ∧ Demanded reads (support owner) read := by
  induction owners with
  | nil =>
    constructor
    · intro demanded
      induction demanded with
      | root _ member => cases member
      | dependency _ _ _ _ ih =>
        obtain ⟨_, member, _⟩ := ih
        cases member
    · rintro ⟨_, member, _⟩; cases member
  | cons owner rest ih =>
    simp only [List.flatMap_cons, demanded_append, ih, List.mem_cons]
    constructor
    · rintro (here | ⟨other, member, reached⟩)
      · exact ⟨owner, Or.inl rfl, here⟩
      · exact ⟨other, Or.inr member, reached⟩
    · rintro ⟨other, same | member, reached⟩
      · subst other; exact Or.inl reached
      · exact Or.inr ⟨other, member, reached⟩

/-- The existing indexed forward walk supplies owners. Construct its root
projection once; every effect boundary still validates all demanded records.
No catalog enumeration or successful-currentness cache is used by this law. -/
theorem projected_current_exact (modules : Owner → List Owner) (reads : Read → List Read)
    (shared : List Read) (support : Owner → List Read) (selected owners : List Owner)
    (complete : ∀ owner, owner ∈ owners ↔ Demanded modules selected owner)
    (fresh : Read → Prop) :
    Current reads (scopeRoots shared owners support) fresh ↔
      ScopeCurrent modules reads shared support selected fresh := by
  rw [scopeRoots, current_append]
  constructor
  · rintro ⟨sharedCurrent, ownerCurrent⟩
    refine ⟨sharedCurrent, ?_⟩
    intro owner reached read demanded
    exact ownerCurrent read ((demanded_owner_roots reads owners support read).mpr
      ⟨owner, (complete owner).mpr reached, demanded⟩)
  · rintro ⟨sharedCurrent, ownerCurrent⟩
    refine ⟨sharedCurrent, ?_⟩
    intro read demanded
    obtain ⟨owner, member, localDemand⟩ :=
      (demanded_owner_roots reads owners support read).mp demanded
    exact ownerCurrent owner ((complete owner).mp member) read localDemand

private theorem no_edges_demand {Node : Type} (roots : List Node) (node : Node) :
    Demanded (fun _ => []) roots node ↔ node ∈ roots := by
  constructor
  · intro demanded
    cases demanded with
    | root _ member => exact member
    | dependency _ _ _ edge => cases edge
  · exact .root node

/-- Owner demand is intentionally weaker than certifying every publication.
This is NOT a drop-in equivalence to today's global link guard. Shared facts
must still contain every genuinely global policy obligation. -/
theorem local_scope_does_not_certify_unselected_owner :
    ScopeCurrent (fun (_ : Bool) => []) (fun (_ : Bool) => []) []
      (fun owner => [owner]) [false] (fun read => read = false) ∧
    ¬ Current (fun (_ : Bool) => []) [false, true] (fun read => read = false) := by
  constructor
  · constructor
    · intro read demanded
      have empty := (no_edges_demand [] read).mp demanded
      cases empty
    · intro owner reached read demanded
      have own : owner = false := by simpa using (no_edges_demand [false] owner).mp reached
      subst owner
      simpa using (no_edges_demand [false] read).mp demanded
  · intro current
    have impossible := current true (.root true (by simp))
    cases impossible

end ScopeProjection

namespace TrackedEdit
open Loading.IncrementalRoles

/-- Registration is about actual POO read receivers, including shared Type and
policy inputs. A Module-only requires graph cannot supply this premise. -/
def Covers (dependencies : Read → List Read) (roots : Owner → List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop) : Prop :=
  ∀ owner read, Demanded dependencies (roots owner) read → registered owner (receiver read)

/-- A completed old reverse-index walk excludes every changed receiver in an
unaffected certificate's original support. No directory roster is inspected. -/
theorem clean_owner_has_no_changed_read
    (dependencies : Read → List Read) (roots : Owner → List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop)
    (changed : Owner → Prop) (owner : Owner)
    (complete : Covers dependencies roots receiver registered)
    (clean : ¬ Affected registered changed owner)
    (read : Read) (demanded : Demanded dependencies (roots owner) read) :
    ¬ changed (receiver read) := by
  intro modified
  exact clean (.consumer (complete owner read demanded) (.source modified))

/-- Transport only after the native writer proves coverage of EVERY changed
freshness fact. Raw table/route edits, unknown callbacks and filesystem writes
cannot be certified by a receiver revision or ticket number alone.
Signed dependency lists and retained roots still belong to this captured cut. -/
theorem retain_current_after_tracked_edit
    (dependencies : Read → List Read) (roots : Owner → List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop)
    (changed : Owner → Prop) (before after : Read → Prop) (owner : Owner)
    (complete : Covers dependencies roots receiver registered)
    (writerFrame : ∀ read, ¬ changed (receiver read) → before read → after read)
    (old : Current dependencies (roots owner) before)
    (clean : ¬ Affected registered changed owner) :
    Current dependencies (roots owner) after := by
  intro read demanded
  exact writerFrame read
    (clean_owner_has_no_changed_read dependencies roots receiver registered changed owner
      complete clean read demanded)
    (old read demanded)

/-- An unaffected owner carries exactly its former demand through a commit.
The native writer must keep its original root spine and the signed edges of
each unchanged receiver. This condition is separate from live slot freshness:
an unreported new edge would otherwise let a transported verdict miss a read. -/
theorem retained_demand_matches_successor
    (prior next : Read → List Read) (roots : Owner → List Read) (nextRoots : List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop)
    (changed : Owner → Prop) (owner : Owner)
    (complete : Covers prior roots receiver registered)
    (clean : ¬ Affected registered changed owner)
    (rootFrame : nextRoots = roots owner)
    (edgeFrame : ∀ read, ¬ changed (receiver read) → next read = prior read)
    (read : Read) : Demanded next nextRoots read ↔ Demanded prior (roots owner) read := by
  subst nextRoots
  have framed : ∀ read, Demanded prior (roots owner) read → next read = prior read :=
    fun read demand => edgeFrame read
      (clean_owner_has_no_changed_read prior roots receiver registered changed owner
        complete clean read demand)
  constructor
  · intro demand
    induction demand with
    | root read member => exact .root read member
    | dependency parent child _ edge ih =>
      exact .dependency parent child ih (by simpa [framed parent ih] using edge)
  · intro demand
    induction demand with
    | root read member => exact .root read member
    | dependency parent child oldDemand edge ih =>
      exact .dependency parent child ih (by simpa [framed parent oldDemand] using edge)

theorem retain_current_in_successor
    (prior next : Read → List Read) (roots : Owner → List Read) (nextRoots : List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop)
    (changed : Owner → Prop) (before after : Read → Prop) (owner : Owner)
    (complete : Covers prior roots receiver registered)
    (clean : ¬ Affected registered changed owner)
    (rootFrame : nextRoots = roots owner)
    (edgeFrame : ∀ read, ¬ changed (receiver read) → next read = prior read)
    (writerFrame : ∀ read, ¬ changed (receiver read) → before read → after read)
    (old : Current prior (roots owner) before) : Current next nextRoots after := by
  intro read demand
  have original := (retained_demand_matches_successor prior next roots nextRoots receiver
    registered changed owner complete clean rootFrame edgeFrame read).mp demand
  exact retain_current_after_tracked_edit prior roots receiver registered changed before after
    owner complete writerFrame old clean read original

/-- The exact signed edge frame preserves deterministic traversal as well as
demand membership. Each fixed indexed traversal therefore has the same
ordered projection when its membership index represents the seen list. -/
theorem retained_preorder_matches_successor [DecidableEq Read]
    (prior next : Read → List Read) (roots : Owner → List Read) (nextRoots : List Read)
    (receiver : Read → Owner) (registered : Owner → Owner → Prop)
    (changed : Owner → Prop) (owner : Owner)
    (complete : Covers prior roots receiver registered)
    (clean : ¬ Affected registered changed owner)
    (rootFrame : nextRoots = roots owner)
    (edgeFrame : ∀ read, ¬ changed (receiver read) → next read = prior read)
    (fuel : Nat) : discover next fuel ⟨[], nextRoots⟩ = discover prior fuel ⟨[], roots owner⟩ := by
  subst nextRoots
  apply discover_agrees_inside prior next (Demanded prior (roots owner))
  · exact fun parent demand child edge => Demanded.dependency parent child demand edge
  · intro read demand
    exact edgeFrame read (clean_owner_has_no_changed_read prior roots receiver registered
      changed owner complete clean read demand)
  · constructor
    · simp
    · exact Demanded.root

/-- Identical roots and a live old root can still miss newly required support
when the native writer omits a change to a signed edge. -/
theorem retained_root_alone_cannot_certify_successor :
    Current (fun _ : Bool => []) [false] (· = false) ∧
      ¬ Current (fun _ : Bool => [true]) [false] (· = false) := by
  constructor
  · intro read demand
    cases demand with
    | root read member => simpa using member
    | dependency parent child _ edge => simp at edge
  · intro current
    have impossible := current true (.dependency false true (.root false (by simp)) (by simp))
    cases impossible

/-- Root projections come from the SAME immutable bundle as the returned
certificate and index. Concurrent publication cannot retarget a successful
read's roots to another generation while retaining an old verdict. -/
theorem publication_read_keeps_current_roots
    (snapshot : Loading.DependencyPublication.State)
    (edits : List Loading.DependencyPublication.Edit)
    (owner certificate : Nat) (consumers : List Nat) (entryOK returnOK : Bool)
    (dependencies : Loading.DependencyPublication.Bundle → Read → List Read)
    (roots : Loading.DependencyPublication.Bundle → Nat → List Read)
    (receiver : Read → Nat) (registered : Nat → Nat → Prop)
    (changed : Nat → Prop) (before after : Read → Prop)
    (served : Loading.DependencyPublication.read snapshot
      (Loading.DependencyPublication.run snapshot edits) owner entryOK returnOK =
        some (certificate, consumers))
    (complete : Covers (dependencies snapshot.bundle) (roots snapshot.bundle) receiver registered)
    (writerFrame : ∀ read, ¬ changed (receiver read) → before read → after read)
    (old : Current (dependencies snapshot.bundle) (roots snapshot.bundle owner) before)
    (clean : ¬ Affected registered changed owner) :
    Current (dependencies (Loading.DependencyPublication.run snapshot edits).bundle)
      (roots (Loading.DependencyPublication.run snapshot edits).bundle owner) after := by
  rw [Loading.DependencyPublication.successful_read_keeps_view snapshot edits owner
    certificate consumers entryOK returnOK served]
  exact retain_current_after_tracked_edit _ _ receiver registered changed before after owner
    complete writerFrame old clean

/-- A missing registration for a shared provider makes a falsely clean owner
appear reusable. The fixed writer frame can hold while the old certificate is
stale; complete read registration is indispensable. -/
theorem incomplete_index_can_miss_stale_support :
    let dependencies : Unit → List Unit := fun _ => []
    let roots : Nat → List Unit := fun _ => [()]
    let changed : Nat → Prop := fun owner => owner = 1
    let registered : Nat → Nat → Prop := fun _ _ => False
    let before : Unit → Prop := fun _ => True
    let after : Unit → Prop := fun _ => False
    Current dependencies (roots 0) before ∧
      (¬ Affected registered changed 0) ∧
      (∀ read : Unit, ¬ changed (1 : Nat) → before read → after read) ∧
      ¬ Current dependencies (roots 0) after := by
  dsimp only
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro _ _; trivial
  · intro affected
    cases affected with
    | source modified => simp at modified
    | consumer edge _ => exact edge
  · intro _ unmodified _
    exact unmodified rfl
  · intro current
    exact current () (.root () (by simp))

/-- Even a complete index does not authorize reuse after an untracked edit.
Here no changed receiver was reported, yet an actual read became stale. -/
theorem untracked_write_cannot_transport_currentness :
    let dependencies : Unit → List Unit := fun _ => []
    let roots : Unit → List Unit := fun _ => [()]
    let receiver : Unit → Unit := id
    let registered : Unit → Unit → Prop := fun _ _ => True
    let changed : Unit → Prop := fun _ => False
    let before : Unit → Prop := fun _ => True
    let after : Unit → Prop := fun _ => False
    Covers dependencies roots receiver registered ∧
      Current dependencies (roots ()) before ∧
      (¬ Affected registered changed ()) ∧
      ¬ Current dependencies (roots ()) after := by
  dsimp only
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro _ _ _; trivial
  · intro _ _; trivial
  · intro affected
    have impossible : ∀ owner : Unit,
        ¬ Affected (fun (_ _) => True) (fun _ => False) owner := by
      intro owner dirty
      induction dirty with
      | source modified => exact modified
      | consumer _ _ ih => exact ih
    exact impossible () affected
  · intro current
    exact current () (.root () (by simp))

end TrackedEdit

/-- An exact input observation can serve several owners when the authority
binds the expected value and guarantees the same observation at each use.
`owners` are the consumers of this one input, not the entire directory. -/
theorem shared_source_input_exact {Owner Input : Type}
    (owners : List Owner) (expected observed : Input) (atUse : Owner → Input)
    (sameCut : ∀ owner ∈ owners, atUse owner = observed) :
    (∀ owner ∈ owners, atUse owner = expected) ↔
      (owners = [] ∨ observed = expected) := by
  constructor
  · intro checked
    cases owners with
    | nil => exact Or.inl rfl
    | cons first rest =>
      have member : first ∈ first :: rest := List.mem_cons_self ..
      exact Or.inr ((sameCut first member).symm.trans (checked first member))
  · intro result owner member
    rcases result with empty | checked
    · simp [empty] at member
    · exact (sameCut owner member).trans checked

/-- Reusing the old input at a second checkpoint can accept a changed
source, even when both owners require exactly the same input identity. -/
theorem shared_input_identity_does_not_cross_effect :
    let owners := [false, true]
    let expected := false
    let firstObservation := false
    let afterEffect := id (α := Bool)
    firstObservation = expected ∧
      ¬ (∀ owner ∈ owners, afterEffect owner = expected) := by
  constructor
  · rfl
  · intro checked
    have stale := checked true (by simp)
    simp at stale

/-- A source probe with no revision authority only learns the positions it
reads. Omitting one position leaves a changed input indistinguishable from
the expected input, even when the size and every observed position agree. -/
theorem omitted_source_position_can_hide_edit {size : Nat}
    (expected : Fin size → Bool) (positions : List (Fin size))
    (omitted : Fin size) (missing : omitted ∉ positions) :
    ∃ live : Fin size → Bool,
      (∀ position ∈ positions, live position = expected position) ∧ live ≠ expected := by
  let live := fun position => if position = omitted then !expected position else expected position
  refine ⟨live, ?_, ?_⟩
  · intro position member
    have distinct : position ≠ omitted := fun equal => missing (equal ▸ member)
    simp [live, distinct]
  · intro equal
    have atEdit := congrFun equal omitted
    cases bit : expected omitted <;> simp [live, bit] at atEdit

/-- Exact full comparison from a finite probe requires coverage of every
position when the contents can change independently at an effect boundary. -/
theorem exact_source_probe_iff_complete {size : Nat}
    (expected : Fin size → Bool) (positions : List (Fin size)) :
    (∀ live : Fin size → Bool,
      (∀ position ∈ positions, live position = expected position) → live = expected) ↔
    ∀ position, position ∈ positions := by
  constructor
  · intro exactProbe position
    by_cases member : position ∈ positions
    · exact member
    · obtain ⟨live, agrees, different⟩ :=
        omitted_source_position_can_hide_edit expected positions position member
      exact False.elim (different (exactProbe live agrees))
  · intro complete live agrees
    funext position
    exact agrees position (complete position)

-- Runtime correspondence premises remain: eq?-identity normalization,
-- unmodified original dependency lists, public replay's final recheck,
-- unchanged real observer delivery, and no nonlocal continuation escape.
-- This does not prove Gerbil source ownership, GC behavior or a memory byte bound.

end YuanxuProof.ModuleSystem.Graph.PublicationReads
