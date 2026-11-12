-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.Admission.SourceWindows
import YuanxuProof.Admission.ReadOnlyEntry
import LeanPoo.Functional.CacheLookup

/-! Composition of structurally checked operations, without a result cache.
`checked` requires extraction of the actual paired procedure and exact guard;
it is not a user-supplied purity assertion. Matching Scheme metadata, passive
source guards and stable pure intervals remain correspondence premises. -/
namespace YuanxuProof.Admission.BoundaryComposition
open SourceWindows

abbrev Action := World → Option World

inductive Operation where
  | checked (action : Action) (tailAvailable : World → Bool)
  | opaque (action : Action)

def guarded (valid : World → Bool) (action : Action) (world : World) : Option World :=
  if valid world then
    (action world).bind (fun next => if valid next then some next else none)
  else none

-- Original wrapper composition: each checked call owns both boundaries,
-- and the enclosing caller also checks the final world.
def originalTail (valid : World → Bool) : List Operation → World → Option World
  | [], world => if valid world then some world else none
  | .checked action _ :: rest, world =>
      (guarded valid action world).bind (originalTail valid rest)
  | .opaque action :: rest, world =>
      (action world).bind (originalTail valid rest)

-- The local bit describes only the immediately preceding closed boundary.
-- Opaque code clears it. Metadata invalidation may conservatively clear it too.
def normalizedTail (valid : World → Bool) : List Operation → Bool → World → Option World
  | [], known, world => if known || valid world then some world else none
  | .checked action available :: rest, known, world =>
      if known || valid world then
        (action world).bind (fun next =>
          if valid next then normalizedTail valid rest (available next) next else none)
      else none
  | .opaque action :: rest, _, world =>
      (action world).bind (normalizedTail valid rest false)

theorem tail_equivalent (valid : World → Bool) (operations : List Operation)
    (known : Bool) (world : World) (sound : known = true → valid world = true) :
    normalizedTail valid operations known world = originalTail valid operations world := by
  induction operations generalizing known world with
  | nil =>
      cases h : known <;> simp_all [normalizedTail, originalTail]
  | cons operation rest ih =>
      cases operation with
      | «opaque» action =>
          simp only [normalizedTail, originalTail]
          cases h : action world with
          | none => simp
          | some next => simpa using ih false next (by simp)
      | checked action available =>
          have entry : (known || valid world) = valid world := by
            cases h : known <;> simp_all
          simp only [normalizedTail, originalTail, guarded, entry]
          cases before : valid world with
          | false => simp
          | true =>
              simp only [↓reduceIte]
              cases result : action world with
              | none => simp
              | some next =>
                  cases after : valid next with
                  | false => simp [after]
                  | true =>
                      simpa [result, after] using (ih (available next) next (by intro _; exact after))

def original (valid : World → Bool) (operations : List Operation) (world : World) :=
  if valid world then originalTail valid operations world else none

def normalized (valid : World → Bool) (operations : List Operation) (world : World) :=
  if valid world then normalizedTail valid operations true world else none

theorem composition_equivalent (valid : World → Bool) (operations : List Operation)
    (world : World) : normalized valid operations world = original valid operations world := by
  cases current : valid world with
  | false => simp [normalized, original, current]
  | true => simpa [normalized, original, current] using
      tail_equivalent valid operations true world (by intro _; exact current)

theorem changed_after_action_rejected (valid : World → Bool) (action : Action)
    (available : World → Bool) (rest : List Operation) (known : Bool) (world next : World)
    (changed : action world = some next) (stale : valid next = false) :
    normalizedTail valid (.checked action available :: rest) known world = none := by
  simp [normalizedTail, changed, stale]

-- Reuse the existing actual byte-check model; no epoch oracle or new cache.
def bytesValid (inputs : List (String × String)) (world : World) : Bool :=
  (check inputs world empty).accepted

private def old : World := fun _ => some "old"
private def changed : World := fun _ => some "changed"
private def valid := bytesValid [("config.ss", "old")]
private def repair : Operation := .checked (fun _ => some old) (fun _ => true)

-- An opaque callback may write AFTER its own check. Its successor must refuse
-- before executing even a "repair" action that would hide that source change.
#guard (normalized valid [.opaque (fun _ => some changed), repair] old).isNone
-- Unsound carry across that callback would wrongly allow repair/publication.
#guard (normalizedTail valid [repair] true changed).isSome

#print axioms composition_equivalent
#print axioms changed_after_action_rejected

/-! Constructor-to-registry extraction for compiler metadata. The registry owns
the procedure returned by the source constructor, not a `pure` field supplied
by its caller. Revisions include its actual prototype ancestry. No successful
source/admission result appears in this record. -/
namespace SourceGuards
open ReadOnlyEntry
open ReplayBoundary (Request)

structure Origin where
  receiver : Nat
  checker : Nat
  revisions : List Nat
  requests : List Request
  context : Option Nat

structure Live where
  constructorRef : Nat
  receiver : Nat
  checker : Nat
  revisions : List Nat
  protocol : Bool
  observer : Option Nat
  selectedChecker : Option Nat
  selectedProtocol : Bool
  selectedIdentity : Option Nat
  packageCacheHot : Bool
  protectedMetadataMiss : Bool
  selectedOrigin : Option Origin
  selectedReceiver : Nat
  selectedRevisions : List Nat
  selectedPackageHot : Bool
  scopeOwner : Option Nat
  graphOwner : Nat
  graphRevisions : List Nat
  birthGraphRevisions : List Nat

def registeredProgram (origin : Origin) : List Entry :=
  match origin.context with
  | none => sourceEntries none origin.requests
  | some context => [.opaque (.checker context)]

-- A different closure is accepted only through its OWN constructor binding.
-- This does not equate closures or discard either source-check obligation.
def selectedNative (checker : Nat) (live : Live) : Bool :=
  match live.selectedOrigin with
  | none => false
  | some own => own.context.isNone && live.selectedReceiver == own.receiver &&
      checker == own.checker && live.selectedRevisions == own.revisions && live.selectedPackageHot

def selectedProgram (origin : Origin) (live : Live) : List Entry :=
  match live.selectedChecker with
  | none => []
  | some checker =>
      if checker == origin.checker then registeredProgram origin
      else match live.selectedOrigin with
        | some own => registeredProgram own
        | none => [.opaque (.checker checker)]

def guardedProgram (origin : Origin) (live : Live) :=
  registeredProgram origin ++ selectedProgram origin live

def sameOrigin (origin : Origin) (live : Live) : Bool :=
  live.constructorRef == 0 && live.receiver == origin.receiver && live.checker == origin.checker &&
  live.revisions == origin.revisions && !live.protocol && live.observer.isNone &&
  live.packageCacheHot && !live.protectedMetadataMiss &&
  live.graphRevisions == live.birthGraphRevisions &&
  (match live.scopeOwner with | none => true | some owner => owner == live.graphOwner) &&
    match live.selectedChecker with
    | none => true
    | some selected => (selected == origin.checker || selectedNative selected live) &&
        !live.selectedProtocol && live.selectedIdentity.isSome

def inspectSource (origin : Origin) (live : Live) :=
  if sameOrigin origin live then lower (guardedProgram origin live)
  else .error (.checker live.checker)

theorem accepted_uses_registered_program (origin : Origin) (live : Live)
    (program : List ClosedOp) (accepted : inspectSource origin live = .ok program) :
    lower (guardedProgram origin live) = .ok program := by
  unfold inspectSource at accepted
  split at accepted
  · exact accepted
  · cases accepted

theorem accepted_has_no_callback (origin : Origin) (live : Live)
    (program : List ClosedOp) (accepted : inspectSource origin live = .ok program) :
    ∀ exposure, Entry.opaque exposure ∉ guardedProgram origin live :=
  successful_lowering_no_callbacks _ _ (accepted_uses_registered_program _ _ _ accepted)

theorem changed_checker_refuses (origin : Origin) (live : Live)
    (changed : live.checker ≠ origin.checker) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, changed]

theorem changed_constructor_refuses (origin : Origin) (live : Live)
    (changed : live.constructorRef ≠ 0) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, changed]

theorem changed_ancestry_refuses (origin : Origin) (live : Live)
    (changed : live.revisions ≠ origin.revisions) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, changed]

theorem observer_refuses (origin : Origin) (live : Live) (observer : Nat)
    (installed : live.observer = some observer) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, installed]

theorem inherited_graph_owner_refuses (origin : Origin) (live : Live) (child : Nat)
    (scopeEq : live.scopeOwner = some child) (different : child ≠ live.graphOwner) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, scopeEq, different]

theorem changed_graph_refuses (origin : Origin) (live : Live)
    (changed : live.graphRevisions ≠ live.birthGraphRevisions) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, changed]

theorem selected_open_context_refuses (checker : Nat) (live : Live) (own : Origin)
    (present : live.selectedOrigin = some own) (context : Nat)
    (opaqueBody : own.context = some context) : selectedNative checker live = false := by
  simp [selectedNative, present, opaqueBody]

theorem selected_changed_checker_refuses (checker : Nat) (live : Live) (own : Origin)
    (present : live.selectedOrigin = some own) (changed : checker ≠ own.checker) :
    selectedNative checker live = false := by
  simp [selectedNative, present, changed]

theorem selected_changed_receiver_refuses (checker : Nat) (live : Live) (own : Origin)
    (present : live.selectedOrigin = some own) (changed : live.selectedReceiver ≠ own.receiver) :
    selectedNative checker live = false := by
  simp [selectedNative, present, changed]

theorem selected_changed_revision_refuses (checker : Nat) (live : Live) (own : Origin)
    (present : live.selectedOrigin = some own) (changed : live.selectedRevisions ≠ own.revisions) :
    selectedNative checker live = false := by
  simp [selectedNative, present, changed]

-- The private bound origin, not a filename's latest cache entry, is the input
-- to live comparison. The entire selected body is appended in source order.
theorem distinct_selected_keeps_both_bodies (origin own : Origin) (live : Live) (checker : Nat)
    (present : live.selectedOrigin = some own) (selected : live.selectedChecker = some checker)
    (different : checker ≠ origin.checker) :
    guardedProgram origin live = registeredProgram origin ++ registeredProgram own := by
  simp [guardedProgram, selectedProgram, present, selected, different]

-- A cold official package-cache lookup can invoke its reader; metadata cache
-- filling can invalidate a protected miss. Neither belongs in a closed prefix.
theorem warm_package_omits_reader {Item Fault : Type} (value : Item)
    (reader : Unit → Except Fault Item) :
    LeanPoo.Functional.ConstructionCache.lookupOr (some value) reader = .ok value :=
  LeanPoo.Functional.ConstructionCache.lookupOr_present value reader

theorem cold_package_refuses (origin : Origin) (live : Live)
    (cold : live.packageCacheHot = false) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, cold]

theorem protected_miss_refuses (origin : Origin) (live : Live)
    (cold : live.protectedMetadataMiss = true) :
    inspectSource origin live = .error (.checker live.checker) := by
  simp [inspectSource, sameOrigin, cold]

theorem open_constructor_refuses (origin : Origin) (live : Live) (context : Nat)
    (callback : origin.context = some context) :
    inspectSource origin live = .error (.checker live.checker) ∨
      inspectSource origin live = .error (.checker context) := by
  unfold inspectSource
  split
  · exact Or.inr (by simp [guardedProgram, registeredProgram, callback, lower])
  · exact Or.inl rfl

-- Instrument the EXISTING executor, rather than erase authentication steps.
-- The trace retains each operation occurrence, including repeated token keys.
def visited : List ClosedOp → Window → List ClosedOp
  | [], _ => []
  | operation :: rest, state =>
      operation :: match one operation state with
        | .error _ => []
        | .ok next => visited rest next

def requiredTrace : List ClosedOp → World → List ClosedOp
  | [], _ => []
  | operation :: rest, world =>
      operation :: if (firstFault [operation] world).isNone then requiredTrace rest world else []

theorem visited_exact (program : List ClosedOp) (state : Window)
    (sound : Sound state.bytes state.files) :
    visited program state = requiredTrace program state.files := by
  induction program generalizing state with
  | nil => rfl
  | cons operation rest ih =>
    cases operation with
    | token key current =>
        cases current <;> simp [visited, one, requiredTrace, firstFault, ih state sound]
    | order result =>
        cases result <;> simp [visited, one, requiredTrace, firstFault, ih state sound, Except.map, Except.mapError]
    | source request =>
        simp only [visited, one, requiredTrace, firstFault]
        rw [fetch_value state.bytes state.files request.path sound]
        by_cases matching : state.files request.path = some request.expected
        · simp only [matching, BEq.rfl, ↓reduceIte, Option.isNone_none]
          exact congrArg (ClosedOp.source request :: ·)
            (ih {state with bytes := (fetch state.bytes state.files request.path).2}
                (fetch_sound state.bytes state.files request.path sound))
        · simp [matching]

theorem closed_window_keeps_authentication_trace (program : List ClosedOp)
    (left right : Window) (same : left.files = right.files)
    (leftSound : Sound left.bytes left.files) (rightSound : Sound right.bytes right.files) :
    visited program left = visited program right := by
  rw [visited_exact _ _ leftSound, visited_exact _ _ rightSound, same]

/-- Existing ordered MOP/source execution theorem supplies the common result;
reusing bytes in a closed segment cannot change the first diagnostic. -/
theorem closed_window_diagnostic (program : List ClosedOp)
    (left right : Window) (same : left.files = right.files)
    (leftSound : Sound left.bytes left.files) (rightSound : Sound right.bytes right.files) :
    failure (execute program left) = failure (execute program right) := by
  rw [ordered_failure_exact _ _ leftSound, ordered_failure_exact _ _ rightSound, same]

/-- A new byte interval is not permission to reorder or omit operations. -/
def executeBlocks : List (List ClosedOp) → Window → Except Fault Window
  | [], state => .ok state
  | block :: rest, state =>
      (execute block {state with bytes := empty}).bind (executeBlocks rest)

theorem firstFault_append (left right : List ClosedOp) (world : World) :
    firstFault (left ++ right) world =
      (firstFault left world).orElse (fun _ => firstFault right world) := by
  induction left with
  | nil => rfl
  | cons operation rest ih =>
    cases operation with
    | token key current => cases current <;> simp [firstFault, ih]
    | order result => cases result <;> simp [firstFault, ih]
    | source request =>
      by_cases matching : (world request.path == some request.expected) = true
      · simp [firstFault, matching, ih]
      · simp [firstFault, matching]

/-- All blocks are already lowered: opaque calls remain outside them. Each
block starts fresh; only its own byte reads share. Identity and candidate are
still carried by the existing executor, not an admission result. -/
theorem blocks_keep_first_diagnostic (blocks : List (List ClosedOp)) (state : Window) :
    ReadOnlyEntry.failure (executeBlocks blocks state) = firstFault blocks.flatten state.files := by
  induction blocks generalizing state with
  | nil => rfl
  | cons block rest ih =>
    have exact := ordered_failure_exact block {state with bytes := empty}
      (empty_sound state.files)
    rw [List.flatten_cons, firstFault_append]
    cases head : execute block {state with bytes := empty} with
    | error issue =>
      have fault : firstFault block state.files = some issue := by
        simpa [head, ReadOnlyEntry.failure] using exact.symm
      simp [executeBlocks, head, fault, ReadOnlyEntry.failure, Except.bind]
    | ok next =>
      have clear : firstFault block state.files = none := by
        simpa [head, ReadOnlyEntry.failure] using exact.symm
      have stable := execute_preserves_protected block {state with bytes := empty} next head
      simpa [executeBlocks, head, clear, Except.bind, stable.1] using ih next

/-- Moving a source-only suffix into its own interval cannot hide a diagnostic
behind the still-fresh publication fence or the final source check. -/
theorem publication_suffix_keeps_diagnostic
    (leading publication suffix tail : List ClosedOp) (state : Window) :
    ReadOnlyEntry.failure (executeBlocks [leading, publication, suffix, tail] state) =
      firstFault (leading ++ publication ++ suffix ++ tail) state.files := by
  simpa [List.append_assoc] using
    blocks_keep_first_diagnostic [leading, publication, suffix, tail] state

/-- Extracted from the installed core-import-module fast branch. A cached
context alone says nothing about a different dynamic import procedure. -/
structure ImportFrame where
  importer : Nat
  coreImporter : Nat
  cachedIdentity : Option Nat
  expectedIdentity : Nat

def importProgram (frame : ImportFrame) : List Entry :=
  if frame.importer == frame.coreImporter &&
      frame.cachedIdentity == some frame.expectedIdentity then []
  else [.opaque (.checker frame.importer)]

theorem native_warm_import_is_empty (frame : ImportFrame)
    (native : frame.importer = frame.coreImporter)
    (warm : frame.cachedIdentity = some frame.expectedIdentity) :
    importProgram frame = [] := by simp [importProgram, native, warm]

theorem foreign_import_remains_opaque (frame : ImportFrame)
    (foreign : frame.importer ≠ frame.coreImporter) :
    importProgram frame = [.opaque (.checker frame.importer)] := by
  simp [importProgram, foreign]

theorem cold_import_remains_opaque (frame : ImportFrame)
    (cold : frame.cachedIdentity = none) :
    importProgram frame = [.opaque (.checker frame.importer)] := by
  simp [importProgram, cold]

/-- Identity projection of the official registry's string-path entries. Other
key families (module symbols and prelude-context objects) do not alias a path.
Native import-source publishes a context only after expansion, by insertion. -/
def registerModule (cache : Nat → Option Nat) (path identity : Nat) : Nat → Option Nat :=
  fun key => if key = path then some identity else cache key

theorem native_put_keeps_warm (cache : Nat → Option Nat) (target expected path identity : Nat)
    (warm : cache target = some expected)
    (sameSource : path = target → identity = expected) :
    registerModule cache path identity target = some expected := by
  by_cases same : target = path
  · subst path
    simp [registerModule, sameSource rfl]
  · simp [registerModule, same, warm]

def registerModules : (Nat → Option Nat) → List (Nat × Nat) → Nat → Option Nat
  | cache, [] => cache
  | cache, item :: rest => registerModules (registerModule cache item.1 item.2) rest

theorem native_puts_keep_warm (cache : Nat → Option Nat) (target expected : Nat)
    (writes : List (Nat × Nat)) (warm : cache target = some expected)
    (sameSource : ∀ item ∈ writes, item.1 = target → item.2 = expected) :
    registerModules cache writes target = some expected := by
  induction writes generalizing cache with
  | nil => exact warm
  | cons item rest ih =>
    exact ih (registerModule cache item.1 item.2)
      (native_put_keeps_warm cache target expected item.1 item.2 warm
        (sameSource item (by simp)))
      (fun next member => sameSource next (by simp [member]))

-- Private registry deletion is NOT a native insertion. Warmth cannot be
-- inferred after arbitrary low-level writes or a source/header epoch change.

theorem warm_module_omits_expansion {Context Fault : Type} (context : Context)
    (expand : Unit → Except Fault Context) :
    LeanPoo.Functional.ConstructionCache.lookupOr (some context) expand = .ok context :=
  LeanPoo.Functional.ConstructionCache.lookupOr_present context expand

/-- Both guard programs still execute. Only their byte-window partition
changes, after actual callback-free lowering. No effect/return boundary follows
from this lemma; opaque import and Make retain their independent windows. -/
theorem warm_import_keeps_guard_diagnostic (before after : List ClosedOp) (state : Window) :
    ReadOnlyEntry.failure (executeBlocks [before ++ after] state) =
      ReadOnlyEntry.failure (executeBlocks [before, after] state) := by
  rw [blocks_keep_first_diagnostic, blocks_keep_first_diagnostic]
  simp

/-- A constructor with the native void context has only its declared source
requests. A filename or a caller-provided purity bit cannot establish this. -/
theorem void_context_uses_source_requests (origin : Origin)
    (voidContext : origin.context = none) :
    registeredProgram origin = sourceEntries none origin.requests := by
  simp [registeredProgram, voidContext]

/-- Header/identity projection is deterministic over the constructor's source
and package observations. The caller still checks the actual context instance
and owner; this law cannot identify a context by its printed module name. -/
theorem checked_snapshot_keeps_metadata (requests : List Request) (files : World)
    (current : ∀ request ∈ requests, files request.path = some request.expected)
    (metadata : List (Option String) → Nat) :
    metadata (requests.map (fun request => files request.path)) =
      metadata (requests.map (fun request => some request.expected)) := by
  apply congrArg metadata
  exact List.map_congr_left current

/-- Projection of inputs-for's actual branch: the native context is the key
of the existing weak origin index, owns is the requested-root test, and check
is the SAME constructor checker called by compiler-tool-input. -/
def resolveBoundOwnerInput {Source Fault : Type} (owns : Source → Bool)
    (known : Option Source) (check : Source → Except Fault Unit)
    (resolve : Unit → Except Fault (Option Source)) : Except Fault (Option Source) :=
  match known with
  | some source => if owns source then (check source).map (fun _ => some source) else resolve ()
  | none => resolve ()

theorem bound_owner_uses_original_checker {Source Fault : Type}
    (owns : Source → Bool) (source : Source) (owned : owns source = true)
    (check : Source → Except Fault Unit) (resolve : Unit → Except Fault (Option Source)) :
    resolveBoundOwnerInput owns (some source) check resolve =
      (check source).map (fun _ => some source) := by
  simp [resolveBoundOwnerInput, owned]

theorem foreign_bound_uses_resolver {Source Fault : Type}
    (owns : Source → Bool) (source : Source) (foreign : owns source = false)
    (check : Source → Except Fault Unit) (resolve : Unit → Except Fault (Option Source)) :
    resolveBoundOwnerInput owns (some source) check resolve = resolve () := by
  simp [resolveBoundOwnerInput, foreign]

theorem missing_bound_uses_resolver {Source Fault : Type} (owns : Source → Bool)
    (check : Source → Except Fault Unit) (resolve : Unit → Except Fault (Option Source)) :
    resolveBoundOwnerInput owns none check resolve = resolve () := rfl

theorem bound_owner_cannot_hide_rejection {Source Fault : Type}
    (owns : Source → Bool) (source : Source) (owned : owns source = true)
    (check : Source → Except Fault Unit) (fault : Fault) (refused : check source = .error fault)
    (resolve : Unit → Except Fault (Option Source)) :
    resolveBoundOwnerInput owns (some source) check resolve = .error fault := by
  rw [bound_owner_uses_original_checker owns source owned check resolve, refused]
  rfl

/-- Specialize the existing extraction and window laws to an owned input.
Both complete guard programs remain; only their byte partition changes. -/
theorem owned_input_keeps_both_guards (origin : Origin) (live : Live)
    (program : List ClosedOp) (accepted : inspectSource origin live = .ok program)
    (state : Window) (fresh : Window)
    (sameFiles : state.files = fresh.files)
    (stateSound : Sound state.bytes state.files)
    (freshSound : Sound fresh.bytes fresh.files) :
    (∀ exposure, Entry.opaque exposure ∉ guardedProgram origin live) ∧
    visited (program ++ program) state = visited (program ++ program) fresh ∧
    failure (executeBlocks [program ++ program] state) =
      failure (executeBlocks [program, program] state) := by
  exact ⟨accepted_has_no_callback origin live program accepted,
    closed_window_keeps_authentication_trace _ _ _ sameFiles stateSound freshSound,
    warm_import_keeps_guard_diagnostic program program state⟩

#print axioms accepted_has_no_callback
#print axioms closed_window_keeps_authentication_trace
#print axioms warm_package_omits_reader
end SourceGuards

end YuanxuProof.Admission.BoundaryComposition
