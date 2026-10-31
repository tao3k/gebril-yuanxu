-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.DFSFrames
import LeanPoo.Prototype.MetaBootstrap
import LeanPoo.C4.ResolverSoundness

/-! Raw-state entry analysis. Procedure references are identity projections, not
user purity declarations. A closed result contains no callback instruction.
Extraction from native state and a stable snapshot remain correspondence gates. -/
namespace YuanxuProof.Admission.ReadOnlyEntry
open ReplayBoundary SourceWindows
open LeanPoo

def quintSourceDigest : String :=
  "sha256:2af1a9ef54448df1f71d8be5bff3cafb65b8b925060c06eacc33b7b4cb3f0d32"

inductive Kind where
  | bootstrap | cacheMiss | value | structural
  deriving DecidableEq, Repr

structure Token where
  identity : Nat
  key : String
  kind : Kind
  revision : Nat
  instanceRef : Option Nat
  valueRef : Nat

structure Receiver where
  revision : Nat
  instanceRef : Option Nat
  tableRecord : Option Nat
  cachedValue : Option Nat
  hasCachedSlot : Bool
  selfProtocol : Bool
  anchorValue : Option Nat
  precedence : Option (List String)
  sealed : Bool

/-- Actual branch conditions of object-read-current?, on its receiver snapshot.
The bootstrap branch does not inspect instance or read-table presence. -/
def nativeCurrent (token : Token) (receiver : Receiver) : Bool :=
  (token.revision == receiver.revision) &&
    match token.kind with
    | .bootstrap => receiver.selfProtocol && receiver.anchorValue == some token.valueRef
    | .cacheMiss => token.instanceRef == receiver.instanceRef && !receiver.hasCachedSlot
    | .value => token.instanceRef == receiver.instanceRef &&
        receiver.tableRecord == some token.identity && receiver.cachedValue == some token.valueRef
    | .structural => token.instanceRef == receiver.instanceRef &&
        receiver.tableRecord == some token.identity

structure Metadata where
  graph : C4.Graph
  root : String
  protocolRef : String → Option Nat

-- Raw protocol references on the selected ancestor closure, not callback bodies.
def noProtocols (metadata : Metadata) : Bool :=
  (C4.LinearizeState.reachable metadata.graph
    (C4.LinearizeState.nodeIndex metadata.graph) metadata.root).all
      (fun id => (metadata.protocolRef id).isNone)

/-- Reuse actual C4 soundness/reachability: a successful cold canonical order
cannot select a hidden ancestor protocol when the closure has none. -/
theorem cold_order_has_no_protocol (metadata : Metadata) (order : List String)
    (closed : noProtocols metadata = true)
    (compiled : C4.linearizeChecked metadata.graph metadata.root = .ok order)
    (id : String) (member : id ∈ order) : metadata.protocolRef id = none := by
  obtain ⟨tail, trace⟩ := C4.linearizeChecked_graph_sound compiled
  have reachable := (C4.LinearizeState.reachable_iff metadata.graph metadata.root id).mpr
    (trace.covers.mp member)
  have absent := List.all_eq_true.mp closed id reachable
  simpa using absent

inductive ClosedOp where
  | token (key : String) (current : Bool)
  | order (result : Except C4.Error (List String))
  | source (request : Request)

inductive Exposure where
  | checker (reference : Nat)
  | coldDispatch
  | observer (reference : Nat)
  deriving DecidableEq, Repr

inductive Entry where
  | closed (operation : ClosedOp)
  | opaque (exposure : Exposure)

structure Frame where
  checkerRef : Nat
  token : Token
  receiver : Receiver
  metadata : Metadata
  requests : List Request

def sourceEntries (observerRef : Option Nat) (requests : List Request) : List Entry :=
  requests.flatMap fun request =>
    (match observerRef with | none => [] | some reference => [.opaque (.observer reference)]) ++
      [.closed (.source request)]

/-- Cold dispatch stays opaque unless every selected prototype has no protocol.
Warm lookup does not invoke a protocol, even if one is installed. -/
def metadataEntries (frame : Frame) : List Entry :=
  match frame.receiver.precedence with
  | some order => [.closed (.order (.ok order))]
  | none =>
    let canonical := Entry.closed (.order (C4.linearizeChecked frame.metadata.graph frame.metadata.root))
    if noProtocols frame.metadata then [canonical] else [canonical, .opaque .coldDispatch]

/-- `kernelRef` projects the exact pinned object-read-current? procedure identity.
A foreign checker never acquires purity merely by returning true. -/
def entries (kernelRef : Nat) (observerRef : Option Nat) (frame : Frame) : List Entry :=
  if frame.checkerRef != kernelRef then [.opaque (.checker frame.checkerRef)]
  else
    let current := nativeCurrent frame.token frame.receiver
    [.closed (.token frame.token.key current)] ++
      if current then metadataEntries frame ++ sourceEntries observerRef frame.requests else []

def lower : List Entry → Except Exposure (List ClosedOp)
  | [] => .ok []
  | .opaque exposure :: _ => .error exposure
  | .closed operation :: rest => (lower rest).map (operation :: ·)

-- All successful plans are derived from raw caches/references/guards above.
-- No `pure?` field, sealed-root shortcut, or arbitrary callback interpreter exists.
def inspect (kernelRef : Nat) (observerRef : Option Nat) (frame : Frame) :=
  lower (entries kernelRef observerRef frame)

theorem lower_source_entries (requests : List Request) :
    lower (sourceEntries none requests) = .ok (requests.map ClosedOp.source) := by
  induction requests with
  | nil => rfl
  | cons request rest ih =>
    change (lower (sourceEntries none rest)).map (ClosedOp.source request :: ·) =
      .ok (ClosedOp.source request :: rest.map ClosedOp.source)
    rw [ih]
    rfl

theorem warm_state_closes (frame : Frame) (kernelRef : Nat) (order : List String)
    (checker : frame.checkerRef = kernelRef)
    (prepared : frame.receiver.precedence = some order) :
    ∃ program, inspect kernelRef none frame = .ok program := by
  cases current : nativeCurrent frame.token frame.receiver <;>
    simp [inspect, entries, checker, current, metadataEntries, prepared,
      lower, lower_source_entries, Except.map]

theorem cold_default_closes (frame : Frame) (kernelRef : Nat)
    (checker : frame.checkerRef = kernelRef)
    (cold : frame.receiver.precedence = none)
    (noHooks : noProtocols frame.metadata = true) :
    ∃ program, inspect kernelRef none frame = .ok program := by
  cases current : nativeCurrent frame.token frame.receiver <;>
    simp [inspect, entries, checker, current, metadataEntries, cold, noHooks,
      lower, lower_source_entries, Except.map]

theorem self_protocol_not_default (metadata : Metadata)
    (present : metadata.protocolRef metadata.root ≠ none) :
    noProtocols metadata ≠ true := by
  intro closed
  have root := (C4.LinearizeState.reachable_iff metadata.graph metadata.root metadata.root).mpr
    C4.Ancestor.self
  have absent := List.all_eq_true.mp closed metadata.root root
  exact present (by simpa using absent)

theorem successful_lowering_no_callbacks (program : List Entry) (closed : List ClosedOp)
    (accepted : lower program = .ok closed) :
    ∀ exposure, Entry.opaque exposure ∉ program := by
  induction program generalizing closed with
  | nil => simp
  | cons entry rest ih =>
    cases entry with
    | «opaque» exposure => simp [lower] at accepted
    | closed operation =>
      cases next : lower rest with
      | error exposure => simp [lower, next, Except.map] at accepted
      | ok tail =>
        intro exposure
        simpa using ih tail next exposure

inductive Fault where
  | admission (issue : Issue)
  | order (issue : C4.Error)
  deriving DecidableEq, Repr

structure Window where
  files : World
  candidate : Binding
  bytes : Bytes

def one (operation : ClosedOp) (state : Window) : Except Fault Window :=
  match operation with
  | .token key current =>
    if current then .ok state else .error (.admission (.staleToken key))
  | .order result => result.mapError Fault.order |>.map (fun _ => state)
  | .source request =>
    let loaded := fetch state.bytes state.files request.path
    if loaded.1 == some request.expected then .ok {state with bytes := loaded.2}
    else .error (.admission (.source request))

def execute : List ClosedOp → Window → Except Fault Window
  | [], state => .ok state
  | operation :: rest, state => (one operation state).bind (execute rest)

def executeEntries (callback : Exposure → Window → Except Fault Window) :
    List Entry → Window → Except Fault Window
  | [], state => .ok state
  | .closed operation :: rest, state =>
      (one operation state).bind (executeEntries callback rest)
  | .opaque exposure :: rest, state =>
      (callback exposure state).bind (executeEntries callback rest)

/-- Successful raw-state lowering is independent of EVERY callback body,
including callbacks that write sources or replace the candidate. -/
theorem lowering_independent (callback : Exposure → Window → Except Fault Window)
    (program : List Entry) (closed : List ClosedOp)
    (lowered : lower program = .ok closed) (state : Window) :
    executeEntries callback program state = execute closed state := by
  induction program generalizing closed state with
  | nil => simp [lower] at lowered; subst closed; rfl
  | cons entry rest ih =>
    cases entry with
    | «opaque» exposure => simp [lower] at lowered
    | closed operation =>
      cases tail : lower rest with
      | error exposure => simp [lower, tail, Except.map] at lowered
      | ok suffix =>
        have same : operation :: suffix = closed := by
          simpa [lower, tail, Except.map] using lowered
        subst closed
        have restSame : executeEntries callback rest = execute suffix :=
          funext (fun next => ih suffix tail next)
        simp only [executeEntries, execute, restSame]

theorem one_preserves_protected (operation : ClosedOp) (before after : Window)
    (success : one operation before = .ok after) :
    after.files = before.files ∧ after.candidate = before.candidate := by
  cases operation with
  | token key current => cases current <;> simp_all [one]
  | order result =>
    cases result <;> simp [one, Except.mapError, Except.map] at success
    cases success
    exact ⟨rfl, rfl⟩
  | source request =>
    simp only [one] at success
    split at success
    · have equal := Except.ok.inj success
      subst after
      exact ⟨rfl, rfl⟩
    · cases success

theorem execute_preserves_protected (program : List ClosedOp) (before after : Window)
    (success : execute program before = .ok after) :
    after.files = before.files ∧ after.candidate = before.candidate := by
  induction program generalizing before with
  | nil =>
    have equal := Except.ok.inj success
    subst after
    exact ⟨rfl, rfl⟩
  | cons operation rest ih =>
    cases first : one operation before with
    | error issue => simp [execute, first, Except.bind] at success
    | ok middle =>
      have next : execute rest middle = .ok after := by simpa [execute, first, Except.bind] using success
      have stable := one_preserves_protected operation before middle first
      have tail := ih middle next
      exact ⟨tail.1.trans stable.1, tail.2.trans stable.2⟩

def firstFault : List ClosedOp → World → Option Fault
  | [], _ => none
  | .token key current :: rest, world =>
    if current then firstFault rest world else some (.admission (.staleToken key))
  | .order result :: rest, world =>
    match result with | .error issue => some (.order issue) | .ok _ => firstFault rest world
  | .source request :: rest, world =>
    if world request.path == some request.expected then firstFault rest world
    else some (.admission (.source request))

def failure : Except Fault Window → Option Fault
  | .error issue => some issue
  | .ok _ => none

/-- Extends ordered diagnostic equality to cold C4 failures, without moving them
or sources. Request message/location and the C4 error remain in the outcome. -/
theorem ordered_failure_exact (program : List ClosedOp) (state : Window)
    (sound : Sound state.bytes state.files) :
    failure (execute program state) = firstFault program state.files := by
  induction program generalizing state with
  | nil => rfl
  | cons operation rest ih =>
    cases operation with
    | token key current =>
      cases current with
      | false => rfl
      | true => exact ih state sound
    | order result =>
      cases result with
      | error issue => rfl
      | ok order => exact ih state sound
    | source request =>
      simp only [execute, one, firstFault]
      rw [fetch_value state.bytes state.files request.path sound]
      by_cases matching : state.files request.path = some request.expected
      · simp only [matching, BEq.rfl, ↓reduceIte, Except.bind]
        exact ih {state with bytes := (fetch state.bytes state.files request.path).2}
          (fetch_sound state.bytes state.files request.path sound)
      · simp [matching, Except.bind, failure]

-- A bootstrap anchor is a function VALUE; its read does not execute that hook.
theorem bootstrap_anchor_read (root : Prototype.MetaPrototype.Bootstrap Context Key Name Value)
    (self : Context) (source : Key → Except String Value) :
    Prototype.MetaPrototype.bootstrapLookup root self source .computeOrder = .ok root.computeOrder :=
  Prototype.MetaPrototype.bootstrapLookup_order root self source

private def boot : Token := ⟨7, "compute-slot", .bootstrap, 0, some 10, 23⟩
private def warm : Receiver := ⟨0, some 10, some 7, some 23, true, true, some 23, some ["root"], true⟩
def clear (receiver : Receiver) : Receiver :=
  {receiver with instanceRef := none, tableRecord := none, cachedValue := none, precedence := none}

theorem bootstrap_still_current_after_clear : nativeCurrent boot (clear warm) = true := by decide

theorem ordinary_record_rejects_clear :
    nativeCurrent {boot with kind := .value} (clear warm) = false := by decide

theorem bootstrap_validity_not_readiness :
    nativeCurrent boot (clear warm) = true ∧ (clear warm).precedence = none := by decide

theorem seal_does_not_change_inspection (kernelRef : Nat) (observerRef : Option Nat)
    (frame : Frame) (flag : Bool) :
    inspect kernelRef observerRef {frame with receiver := {frame.receiver with sealed := flag}} =
      inspect kernelRef observerRef frame := rfl

theorem cold_dispatch_remains_open (frame : Frame) (kernelRef : Nat) (observerRef : Option Nat)
    (checker : frame.checkerRef = kernelRef)
    (current : nativeCurrent frame.token frame.receiver = true)
    (cold : frame.receiver.precedence = none)
    (hook : noProtocols frame.metadata = false) :
    inspect kernelRef observerRef frame = .error .coldDispatch := by
  simp [inspect, entries, checker, current, metadataEntries, cold, hook, lower, Except.map]

end YuanxuProof.Admission.ReadOnlyEntry
