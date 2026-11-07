-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Graph.TestAdmission
import YuanxuProof.Admission.RootCollection

namespace YuanxuProof.ModuleSystem.Graph.SourceClosureWork
open TestAdmission

-- The original generated lexical scope selects a role alias before the
-- outer binding; explicit root/core/require shadowing excludes that alias.
-- Values are arbitrary: equality therefore preserves object identity as well.
def roleAliasLookup {Value : Type} (roles shadowed : List Nat)
    (role outer : Nat → Value) (name : Nat) : Value :=
  if name ∈ roles ∧ name ∉ shadowed then role name else outer name

theorem direct_role_alias_identity {Value : Type} (roles shadowed : List Nat)
    (role outer : Nat → Value) (name : Nat)
    (exported : name ∈ roles) (visible : name ∉ shadowed) :
    roleAliasLookup roles shadowed role outer name = role name := by
  simp [roleAliasLookup, exported, visible]

theorem shadowed_role_alias_keeps_outer {Value : Type} (roles shadowed : List Nat)
    (role outer : Nat → Value) (name : Nat) (hidden : name ∈ shadowed) :
    roleAliasLookup roles shadowed role outer name = outer name := by
  simp [roleAliasLookup, hidden]

-- Stock syntax supplies a conservative inventory of identifiers it can read.
-- Open syntax can acquire bindings during expansion, so it retains all aliases.
def neededRoleAliases (roles : List Nat) (uses : Option (List Nat)) : List Nat :=
  match uses with
  | none => roles
  | some names => roles.filter (fun name => decide (name ∈ names))

theorem stock_role_alias_inventory_exact {Value : Type}
    (roles shadows names : List Nat) (role outer : Nat → Value) (name : Nat)
    (used : name ∈ names) :
    roleAliasLookup (neededRoleAliases roles (some names)) shadows role outer name =
      roleAliasLookup roles shadows role outer name := by
  simp [roleAliasLookup, neededRoleAliases, used]

theorem open_expansion_retains_every_alias (roles : List Nat) :
    neededRoleAliases roles none = roles := rfl

theorem stock_inventory_preserves_owner_resolution {Owner Value : Type}
    (roles shadows names : List Nat) (role outer : Owner → Nat → Value)
    (owner : Owner) (name : Nat) (used : name ∈ names) :
    roleAliasLookup (neededRoleAliases roles (some names)) shadows
        (role owner) (outer owner) name =
      roleAliasLookup roles shadows (role owner) (outer owner) name :=
  stock_role_alias_inventory_exact roles shadows names (role owner) (outer owner) name used

def admitOwnerExpansion {Value : Type} (before : Bool) (expand : Unit → Value × Bool) :
    Option Value :=
  if before then
    let (value, after) := expand ()
    if after then some value else none
  else none

theorem expanded_owner_needs_fresh_return_check {Value : Type}
    (before : Bool) (expand : Unit → Value × Bool) (value : Value)
    (admitted : admitOwnerExpansion before expand = some value) :
    before = true ∧ (expand ()).2 = true := by
  cases before <;> cases expanded : expand () with
  | mk result after => cases after <;> simp_all [admitOwnerExpansion]

inductive RoleSlotRecipe (Name : Type) where
  | role (name : Name) (exports : List Name)
  | alias (role name : Name)

-- The role entry captures its original resolver. An alias must read the
-- actual POO self, including its role overrides, before reading the export.
def ownerSlotRecipe {Owner Name Value : Type}
    (load : Owner → Name → List Name → Value) (read : Value → Name → Value)
    (owner : Owner) : RoleSlotRecipe Name → Value → Value
  | .role name exports => fun _ => load owner name exports
  | .alias role name => fun self => read (read self role) name

def sharedRoleSlot {Owner Name Value : Type}
    (load : Owner → Name → List Name → Value) (read : Value → Name → Value)
    (owner : Owner) (recipe : RoleSlotRecipe Name) (self : Value) : Value :=
  match recipe with
  | .role name exports => load owner name exports
  | .alias role name => read (read self role) name

theorem shared_role_slot_preserves_resolver_and_self
    (load : Owner → Name → List Name → Value) (read : Value → Name → Value)
    (owner : Owner) (recipe : RoleSlotRecipe Name) (self : Value) :
    sharedRoleSlot load read owner recipe self = ownerSlotRecipe load read owner recipe self := by
  cases recipe <;> rfl

example : sharedRoleSlot (fun owner _ _ => owner) (fun self slot => self + slot)
    (0 : Nat) (.alias 1 2) 7 = 10 := rfl

-- A fresh native replay supplies the COMPLETE ordered original token trace.
-- Known callbacks may be omitted only when each is actually an identity effect.
-- Parent collection policy remains native: no signed dependency is rewritten.
theorem pure_support_callbacks_are_identity (observe : World → Nat → World)
    (events : List Nat) (world : World)
    (pureCallbacks : ∀ state token, observe state token = state) :
    events.foldl observe world = world := by
  induction events generalizing world with
  | nil => rfl
  | cons token rest ih => simpa [pureCallbacks] using ih world

theorem pure_support_forwarding_preserves_occurrences
    (prior events : List Nat) (world : World) :
    (YuanxuProof.Admission.RootCollection.mergeCaptured false
      ⟨prior, world⟩ events).roots = prior ++ events := rfl

theorem pure_support_forwarding_preserves_unique_policy
    (prior events : List Nat) (world : World) :
    (YuanxuProof.Admission.RootCollection.mergeCaptured true
      ⟨prior.eraseDups, world⟩ events).roots = (prior ++ events).eraseDups :=
  YuanxuProof.Admission.RootCollection.merge_original_identities prior events world

-- Closed metadata frames can share native read topology within ONE guard.
-- This does not combine checks across effects or retain a successful verdict.
theorem joined_guard_support_exact (deps : Node → List Node) (left right : List Node)
    (node : Node) :
    Demanded deps (left ++ right) node ↔
      Demanded deps left node ∨ Demanded deps right node := by
  constructor
  · intro demanded
    induction demanded with
    | root node member =>
      rcases List.mem_append.mp member with l | r
      · exact Or.inl (Demanded.root node l)
      · exact Or.inr (Demanded.root node r)
    | dependency parent child _ member ih =>
      exact ih.elim
        (fun l => Or.inl (Demanded.dependency parent child l member))
        (fun r => Or.inr (Demanded.dependency parent child r member))
  · have lift (roots : List Node) (included : ∀ n ∈ roots, n ∈ left ++ right)
        (demanded : Demanded deps roots node) : Demanded deps (left ++ right) node := by
      induction demanded with
      | root n member => exact Demanded.root n (included n member)
      | dependency parent child _ member ih => exact Demanded.dependency parent child ih member
    exact fun demanded => demanded.elim
      (lift left (fun n member => List.mem_append_left right member))
      (lift right (fun n member => List.mem_append_right left member))

theorem joined_guard_checks_both (left right : List Node) (current : Node → Bool) :
    (left ++ right).all current = (left.all current && right.all current) := by
  simp

-- A topology hit says which reads to check. Dropping a second freshness
-- pass additionally requires preservation of live observations on its support.
theorem replay_share_of_unchanged_support (roots : List Node)
    (before after : Node → Bool)
    (unchanged : ∀ read ∈ roots, before read = after read) :
    (roots.all before && roots.all after) = roots.all before := by
  have same : roots.all before = roots.all after := by
    induction roots with
    | nil => rfl
    | cons head tail ih =>
      simp only [List.all_cons]
      rw [unchanged head (by simp)]
      rw [ih (fun read member => unchanged read (by simp [member]))]
  rw [← same]
  cases roots.all before <;> rfl

-- Even identical ordered roots and a previously passing check are
-- insufficient when a protected observation changes across an effect.
theorem replay_cannot_share_across_changed_read :
    ([0].all (fun _ : Nat => true) && [0].all (fun _ : Nat => false)) ≠
      [0].all (fun _ : Nat => true) := by decide

-- Model the native hash-route refusal order. Its two wrapper checks
-- observe the same object class when no callback occurs in between.
def hashRouteCheck (wrapper method backend hash test unlocked : Bool) : Except String Unit :=
  if !wrapper then .error "foreign metadata wrapper"
  else if !method then .error "changed metadata ref"
  else if !backend then .error "foreign metadata backend"
  else if !(hash && test && unlocked) then .error "changed metadata hash/test"
  else .ok ()

theorem hash_route_reuse_preserves_refusal_order
    (first second method backend hash test unlocked : Bool) (stable : first = second) :
    (if first then hashRouteCheck second method backend hash test unlocked
      else .error "foreign metadata wrapper") =
      hashRouteCheck first method backend hash test unlocked := by
  subst second
  cases first <;> rfl

-- A native vector layout accessor may replace symbolic field selection
-- only after classification, and only for the same live shape. The shape
-- class and its index route are still validated, in their original order.
def vectorShapeRoute {Shape : Type} (shape : Shape) (shapeClass : Shape → Bool)
    (checkIndex : Shape → Except String Unit) : Except String Unit :=
  if shapeClass shape then checkIndex shape else .error "foreign vector shape"

theorem vector_live_shape_accessor_preserves_route {Shape : Type}
    (symbolic native : Shape) (shapeClass : Shape → Bool)
    (checkIndex : Shape → Except String Unit) (sameLiveShape : native = symbolic) :
    vectorShapeRoute native shapeClass checkIndex =
      vectorShapeRoute symbolic shapeClass checkIndex := by
  rw [sameLiveShape]

theorem vector_shape_route_retains_index_refusal {Shape : Type}
    (shape : Shape) (shapeClass : Shape → Bool)
    (checkIndex : Shape → Except String Unit) (admitted : shapeClass shape = true)
    (cause : String) (refused : checkIndex shape = .error cause) :
    vectorShapeRoute shape shapeClass checkIndex = .error cause := by
  simp [vectorShapeRoute, admitted, refused]

-- An absent index or an uncomputed cell both project to the native
-- missing sentinel. A present false value remains an ordinary value.
def vectorCellQuery {Value : Type} (offset : Option Nat)
    (cells : Nat → Option Value) : Option Value :=
  offset.bind cells

theorem vector_query_keeps_absence_and_false (cells : Nat → Option Bool)
    (missing present : Nat) (empty : cells missing = none)
    (stored : cells present = some false) :
    vectorCellQuery none cells = none ∧
      vectorCellQuery (some missing) cells = none ∧
      vectorCellQuery (some present) cells = some false := by
  simp [vectorCellQuery, empty, stored]

def authenticatedVectorRead {Value : Type} (issued : Bool)
    (route : Except String Unit) (stateCurrent : Bool)
    (query expected : Option Value) [DecidableEq Value] : Except String Unit :=
  if !issued then .error "unissued slot dependency"
  else match route with
  | .error cause => .error cause
  | .ok _ => if stateCurrent && decide (query = expected) then .ok ()
             else .error "stale slot dependency"

theorem vector_fusion_preserves_result {Value : Type} [DecidableEq Value]
    (issued : Bool) (route : Except String Unit) (current : Bool)
    (nativeOffset fusedOffset : Option Nat) (nativeCells fusedCells : Nat → Option Value)
    (expected : Option Value) (sameOffset : nativeOffset = fusedOffset)
    (sameCells : nativeCells = fusedCells) :
    authenticatedVectorRead issued route current (vectorCellQuery nativeOffset nativeCells) expected =
      authenticatedVectorRead issued route current (vectorCellQuery fusedOffset fusedCells) expected := by
  rw [sameOffset, sameCells]

theorem vector_route_refusal_precedes_stale {Value : Type} [DecidableEq Value]
    (cause : String) (query expected : Option Value) :
    authenticatedVectorRead true (.error cause) false query expected = .error cause := rfl

theorem vector_return_still_checks_changed_state {Value : Type} [DecidableEq Value]
    (expected : Option Value) :
    (authenticatedVectorRead true (.ok ()) true expected expected >>= fun _ =>
      authenticatedVectorRead true (.ok ()) false expected expected) =
      .error "stale slot dependency" := by
  simp [authenticatedVectorRead, Bind.bind, Except.bind]

-- Each exact-class check authorizes only reads of that class's native fields.
-- The nested stages model wrapper/ref, layout cells, shape and index refusal.
def guardedRouteField {Fields : Type}
    (exactClass : Bool) (foreign : String) (read : Unit → Fields)
    (validate : Fields → Except String Unit) : Except String Unit :=
  if exactClass then validate (read ()) else .error foreign

theorem route_pinned_field_preserves_validation {Fields : Type}
    (exactClass : Bool) (foreign : String) (named native : Unit → Fields)
    (validate : Fields → Except String Unit)
    (sameField : exactClass = true → named () = native ()) :
    guardedRouteField exactClass foreign named validate =
      guardedRouteField exactClass foreign native validate := by
  cases exactClass with
  | false => rfl
  | true => simp [guardedRouteField, sameField rfl]

theorem route_foreign_class_refuses_before_field {Fields : Type}
    (foreign : String) (native : Unit → Fields)
    (validate : Fields → Except String Unit) :
    guardedRouteField false foreign native validate = .error foreign := rfl

-- A joined issuance preflight may encounter a later frame's error first.
-- Pure failure fallback restores the original diagnostic, without approving a
-- failed joined check even if the independent split retry happens to succeed.
def joinedWithFallback (joined split : Except String Unit) : Except String Unit :=
  match joined with
  | .ok _ => .ok ()
  | .error cause => match split with
    | .error original => .error original
    | .ok _ => .error cause

theorem joined_failure_preserves_original_error (cause original : String) :
    joinedWithFallback (.error cause) (.error original) = .error original := rfl

theorem failed_join_never_approves (cause : String) (split : Except String Unit) :
    joinedWithFallback (.error cause) split ≠ .ok () := by
  cases split <;> simp [joinedWithFallback]

-- One native protected replay still authenticates every token both before
-- and after the fixed source/policy checkpoint. Failure never runs later work.
def protectedCheckpoint (before after : Bool) (work : Except String Unit) : Except String Unit :=
  if before then
    match work with
    | .error cause => .error cause
    | .ok _ => if after then .ok () else .error "metadata"
  else .error "metadata"

theorem checkpoint_requires_both (before after : Bool) (work : Except String Unit)
    (accepted : protectedCheckpoint before after work = .ok ()) :
    before = true ∧ after = true ∧ work = .ok () := by
  cases before <;> cases after <;> cases work <;> simp_all [protectedCheckpoint]

theorem checkpoint_preserves_failure (after : Bool) (cause : String) :
    protectedCheckpoint true after (.error cause) = .error cause := rfl

theorem protected_replay_reduces_authentication_work (visits : Nat) :
    2 * visits ≤ 4 * visits := by omega

private def splitContextChecks
    (authenticate first midpoint second : Except String Unit) : Except String Unit := do
  authenticate
  first
  authenticate
  midpoint
  authenticate
  second
  authenticate

private def joinedContextChecks
    (authenticate first midpoint second : Except String Unit) : Except String Unit := do
  authenticate
  first
  midpoint
  second
  authenticate

-- The native protected frame must keep authentication stable throughout.
-- Both Graph checks and the source/Schema midpoint retain their order.
theorem stable_context_authentication_preserves_first_failure
    (authenticate first midpoint second : Except String Unit) :
    splitContextChecks authenticate first midpoint second =
      joinedContextChecks authenticate first midpoint second := by
  cases authenticate <;> cases first <;> cases midpoint <;> cases second <;> rfl

/-- Only the original private source preparation for the captured context can
extend its path index. A same-name context or unowned checkout grants no alias. -/
def ownedToolAlias (captured associated owned current : Bool) : Bool :=
  captured && associated && owned && current

theorem owned_tool_alias_requires_original_binding (captured associated owned current : Bool)
    (accepted : ownedToolAlias captured associated owned current = true) :
    captured = true ∧ associated = true ∧ owned = true ∧ current = true := by
  cases captured <;> cases associated <;> cases owned <;> cases current <;>
    simp_all [ownedToolAlias]

inductive ToolOrigin where
  | source | installed
  deriving DecidableEq

def toolNeedsSource (origin : ToolOrigin) (ownedBuild : Bool) : Bool :=
  match origin with
  | .source => true
  | .installed => ownedBuild

-- Runtime context identity/name/path project to injective native IDs. The
-- checkout is not the execution version of an already loaded SSI context.
def toolAccepts (captured live : Nat × Nat × Nat) (origin : ToolOrigin)
    (ownedBuild sourceCurrent : Bool) : Bool :=
  captured == live && (!toolNeedsSource origin ownedBuild || sourceCurrent)

theorem installed_prerequisite_uses_native_context (binding : Nat × Nat × Nat)
    (sourceCurrent : Bool) :
    toolAccepts binding binding .installed false sourceCurrent = true := by
  simp [toolAccepts, toolNeedsSource]

theorem owned_tool_source_is_still_required (binding : Nat × Nat × Nat)
    (origin : ToolOrigin) :
    toolAccepts binding binding origin true false = false := by
  cases origin <;> simp [toolAccepts, toolNeedsSource]

theorem changed_native_context_refuses (captured live : Nat × Nat × Nat)
    (origin : ToolOrigin) (ownedBuild sourceCurrent : Bool) (changed : captured ≠ live) :
    toolAccepts captured live origin ownedBuild sourceCurrent = false := by
  simp [toolAccepts, changed]

-- Only a fixed closed checkpoint has no external effect. An open callback
-- retains its return obligation even when it removes its own observer.
def nativeToolBoundary (captured before after : Nat × Nat × Nat)
    (origin : ToolOrigin) (ownedBuild sourceCurrent openBoundary : Bool) : Bool :=
  toolAccepts captured before origin ownedBuild sourceCurrent &&
    (!openBoundary || captured == after)

theorem changed_tool_return_refuses (captured before after : Nat × Nat × Nat)
    (origin : ToolOrigin) (ownedBuild sourceCurrent : Bool) (changed : captured ≠ after) :
    nativeToolBoundary captured before after origin ownedBuild sourceCurrent true = false := by
  simp [nativeToolBoundary, changed]

theorem fixed_tool_checkpoint_needs_no_second_pass (captured before : Nat × Nat × Nat)
    (origin : ToolOrigin) (ownedBuild sourceCurrent : Bool) :
    nativeToolBoundary captured before before origin ownedBuild sourceCurrent false =
      toolAccepts captured before origin ownedBuild sourceCurrent := by
  simp [nativeToolBoundary]

-- Native publication tables insert immutable entries once. Cardinality can
-- identify the existing POO topology slot only under that append-only premise;
-- it does NOT authenticate any receiver revision or source byte.
theorem append_only_same_size_same_rows (saved current : List Node)
    (growth : ∃ suffix, current = saved ++ suffix)
    (sameSize : current.length = saved.length) : current = saved := by
  obtain ⟨suffix, rfl⟩ := growth
  have empty : suffix.length = 0 := by simp only [List.length_append] at sameSize; omega
  have nil : suffix = [] := by
    cases suffix with
    | nil => rfl
    | cons _ _ => simp at empty
  simp [nil]

-- Reader guards grow by cons rather than append. A bounded query key may use
-- their count only while this private immutable-spine premise holds. The
-- check itself still visits every guard in each fresh observation window.
theorem prepend_only_same_size_same_rows (saved current : List Node)
    (growth : ∃ added, current = added ++ saved)
    (sameSize : current.length = saved.length) : current = saved := by
  obtain ⟨added, rfl⟩ := growth
  have empty : added.length = 0 := by
    simp only [List.length_append] at sameSize
    omega
  have nil : added = [] := by
    cases added with
    | nil => rfl
    | cons _ _ => simp at empty
  simp [nil]

theorem flat_guard_checks_every_frame (frames : List (List Node)) (current : Node → Bool) :
    frames.flatten.all current = frames.all (fun roots => roots.all current) := by
  induction frames with
  | nil => simp
  | cons roots rest ih => simp [ih]

def toolOriginQuintDigest : String :=
  "sha256:3b8e1e15e0f5a4af7b07636353cefa9283468b23ab68a318d6aa078c0e68de31"

def checkpointQuintDigest : String :=
  "sha256:d14b132d42c27484614e33eee373bce77c998e6eef023f3584549af8be5d1247"

def quintSourceDigest : String :=
  "sha256:eb42dcbeca6e0f871c2458a91540571c20f0e6bc9b0db1e957ca0cbb4cdb5586"

def sourcePrefixQuintDigest : String :=
  "sha256:05e06b4b0765600a5b121fe585284ec6505061efc0c54db3036fb167c695b48c"

def dependencyContinuationQuintDigest : String :=
  "sha256:6577ed33a88f9979b15586492de9abb75a2a77ac2cffc6f66357e54cc6caf850"

def readerEffectSupportQuintDigest : String :=
  "sha256:a0e9cad7aee1ac46c01a700d292a91096c0b3d1497b7c5d11e3b351db7407ac7"

def candidatePublicationQuintDigest : String :=
  "sha256:8e1ae570aad1decd445d9447fd4e047cfa1b40c8f7bb5ce61accedef92a681ff"

def candidateLocationQuintDigest : String :=
  "sha256:531c33fa1ed0fe79873f5897446fa6569e713026d77e5fb4b794b9a55a40af86"

def compilerEnrollmentQuintDigest : String :=
  "sha256:b0fe90bfc66761c668193d987a26a18258b9bc74bd852047cf311e85b101c898"

def authoringStageQuintDigest : String :=
  "sha256:17f703653d33e59f7271dbb5be310d4a5c97a57e914e1d5f444e72fd79af3699"

def carrierReturnQuintDigest : String :=
  "sha256:b447ebd6770d8ca3fb9c311989522cdb31bff681cd167791a3c0b877a76ceb52"

def carrierAdmissionQuintDigest : String :=
  "sha256:5880421305bd18369237ac7ab2fa71f745707d26f0e9bfa6b9a2dd5638eea4f0"

structure Work (Node : Type) where
  discovery : Discovery Node
  pops : Nat
  edges : Nat

def step [DecidableEq Node] (deps : Node → List Node) (s : Work Node) : Work Node :=
  match s.discovery.pending with
  | [] => s
  | node :: _ =>
    ⟨advance deps s.discovery, s.pops + 1,
      s.edges + (if node ∈ s.discovery.seen then 0 else (deps node).length)⟩

def run [DecidableEq Node] (deps : Node → List Node) : Nat → Work Node → Work Node
  | 0, s => s
  | fuel + 1, s => run deps fuel (step deps s)

-- Counts queue removals, including repeated edges, separately from expansions.
-- Hash lookup, source bytes, runtime macro expansion and GC are not unit-cost
-- consequences of this theorem.
def Accounting (roots : Nat) (s : Work Node) : Prop :=
  s.pops + s.discovery.pending.length = roots + s.edges

theorem step_accounting [DecidableEq Node] (deps : Node → List Node)
    (roots : Nat) (s : Work Node) (h : Accounting roots s) :
    Accounting roots (step deps s) := by
  rcases s with ⟨⟨seen, pending⟩, pops, edges⟩
  cases pending with
  | nil => exact h
  | cons node rest =>
    by_cases found : node ∈ seen
    · simpa [Accounting, step, advance, found, Nat.add_assoc, Nat.add_comm,
        Nat.add_left_comm] using h
    · simp only [Accounting, List.length_cons] at h
      simp [Accounting, step, advance, found, List.length_append]
      omega

theorem run_accounting [DecidableEq Node] (deps : Node → List Node)
    (roots : Nat) (fuel : Nat) (s : Work Node) (h : Accounting roots s) :
    Accounting roots (run deps fuel s) := by
  induction fuel generalizing s with
  | zero => exact h
  | succ fuel ih => exact ih _ (step_accounting deps roots s h)

theorem queue_work_bound [DecidableEq Node] (deps : Node → List Node)
    (roots : List Node) (fuel : Nat) :
    (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).pops ≤
      roots.length + (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).edges := by
  have h := run_accounting deps roots.length fuel ⟨⟨[], roots⟩, 0, 0⟩ (by simp [Accounting])
  unfold Accounting at h
  omega

def charged (deps : Node → List Node) (seen : List Node) : Nat :=
  (seen.map fun node => (deps node).length).sum

theorem step_edge_accounting [DecidableEq Node] (deps : Node → List Node)
    (s : Work Node) (h : s.edges = charged deps s.discovery.seen) :
    (step deps s).edges = charged deps (step deps s).discovery.seen := by
  rcases s with ⟨⟨seen, pending⟩, pops, edges⟩
  cases pending with
  | nil => exact h
  | cons node rest =>
    by_cases found : node ∈ seen <;>
      simp_all [step, advance, charged, Nat.add_comm]

theorem run_edge_accounting [DecidableEq Node] (deps : Node → List Node)
    (fuel : Nat) (s : Work Node) (h : s.edges = charged deps s.discovery.seen) :
    (run deps fuel s).edges = charged deps (run deps fuel s).discovery.seen := by
  induction fuel generalizing s with
  | zero => exact h
  | succ fuel ih => exact ih _ (step_edge_accounting deps s h)

theorem run_projects_discovery [DecidableEq Node] (deps : Node → List Node)
    (fuel : Nat) (s : Work Node) :
    (run deps fuel s).discovery = discover deps fuel s.discovery := by
  induction fuel generalizing s with
  | zero => rfl
  | succ fuel ih =>
    rw [run, ih]
    have projection : (step deps s).discovery = advance deps s.discovery := by
      cases h : s.discovery.pending <;> simp [step, h, advance]
    rw [projection]
    rfl

theorem expanded_identities_unique [DecidableEq Node] (deps : Node → List Node)
    (roots : List Node) (fuel : Nat) :
    (run deps fuel ⟨⟨[], roots⟩, 0, 0⟩).discovery.seen.Nodup := by
  rw [run_projects_discovery]
  exact discover_preserves_unique_reads deps fuel ⟨[], roots⟩ (by simp)

-- A narrower guard is sound only if the operation's ACTUAL support is covered.
-- Four role files, two preceding-prefix and two completed-prefix barriers per
-- publication. Tool/package checks and source preparation are excluded. This
-- is the audited reader/link call-chain cost, not DFS expansion work.
def prefixGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => prefixGuardReads n + 8 * (2 * n + 1)

theorem prefix_guard_reads_quadratic (n : Nat) :
    prefixGuardReads n = 8 * n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [prefixGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

-- The closed directory operation checks only its metadata support. The reader
-- still checks complete source support before any opaque declaration callback.
-- Expansion and Contract admission still have separate full tail checks.
def pairedGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => pairedGuardReads n + 12 * n + 8

theorem paired_guard_reads (n : Nat) :
    pairedGuardReads n = 6 * n * n + 2 * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [pairedGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

theorem paired_prefix_never_more_reads (n : Nat) :
    pairedGuardReads n ≤ prefixGuardReads n := by
  induction n with
  | zero => exact Nat.le_refl 0
  | succ n ih =>
    simp only [pairedGuardReads, prefixGuardReads, Nat.mul_add] at *
    omega

-- Runtime paired selection: complete entry and declaration-return checks for
-- each module, then ONE full closure check before Feature/decision execution.
-- The final Graph check is unchanged and excluded on both sides, as are
-- compiler-tool/package observations. Custom/open paths keep pairedGuardReads.
def declarationGuardReads : Nat → Nat
  | 0 => 0
  | n + 1 => declarationGuardReads n + 8 * n + 4

def dependencyGuardReads (n : Nat) : Nat := declarationGuardReads n + 4 * n

theorem declaration_guard_reads (n : Nat) :
    declarationGuardReads n = 4 * n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [declarationGuardReads, ih, Nat.mul_add, Nat.add_mul]
    omega

theorem dependency_guard_reads (n : Nat) :
    dependencyGuardReads n = 4 * n * n + 4 * n := by
  simp [dependencyGuardReads, declaration_guard_reads]

theorem dependency_guard_savings (n : Nat) :
    pairedGuardReads (n + 1) = dependencyGuardReads (n + 1) + 2 * n * (n + 1) := by
  rw [paired_guard_reads, dependency_guard_reads]
  simp only [Nat.mul_add, Nat.add_mul, Nat.mul_assoc]
  omega

-- Reuse is not an authority token: the closed prefix must preserve EVERY
-- captured source, runtime metadata receiver and ancestor revision. The runtime
-- audit and negative tests establish this premise at the paired call site.
theorem closed_prefix_preserves_entry
    (support : List Node) (expected eligible entry : Node → Nat)
    (checked : ∀ node, node ∈ support → expected node = eligible node)
    (closed : ∀ node, node ∈ support → eligible node = entry node) :
    ∀ node, node ∈ support → expected node = entry node := by
  intro node demanded
  exact (checked node demanded).trans (closed node demanded)

theorem changed_prefix_cannot_reuse (support : List Node)
    (expected entry : Node → Nat) (node : Node)
    (covered : node ∈ support) (changed : expected node ≠ entry node) :
    ¬ (∀ node, node ∈ support → expected node = entry node) := by
  intro accepted
  exact changed (accepted node covered)

-- A narrower guard is sound only if the operation's ACTUAL support is covered.
-- The finite Quint effects explore changes; this theorem quantifies over any
-- identity type and revisions. It cannot certify an opaque Scheme callback's
-- support by inspecting its name or source path.
theorem covered_guard_preserves_currentness
    (required checked : List Node) (before now : Node → Nat)
    (coverage : ∀ node, node ∈ required → node ∈ checked)
    (current : ∀ node, node ∈ checked → before node = now node) :
    ∀ node, node ∈ required → before node = now node := by
  intro node demanded
  exact current node (coverage node demanded)

-- Subject is a reference-identity projection, NOT structural object equality.
-- The runtime producer may normalize raw input into another receiver. Transfer
-- support only to the exact admitted reference saved by the linker. This law
-- does not certify callbacks as pure or eliminate the return-time source guard.
theorem checked_subject_guard_covers {Subject : Type}
    (support : Subject → List Node) (checked stored : Subject)
    (observed : List Node) (before now : Node → Nat)
    (sameSubject : stored = checked)
    (coverage : ∀ node, node ∈ support checked → node ∈ observed)
    (current : ∀ node, node ∈ observed → before node = now node) :
    ∀ node, node ∈ support stored → before node = now node := by
  subst stored
  exact covered_guard_preserves_currentness (support checked) observed before now
    coverage current

-- The caller establishes location-demand ⊆ metadata support from the actual
-- runtime directory implementation; it must not substitute metadata support
-- for the subsequent reader's complete support. Apply the same projection
-- theorem at two DIFFERENT operation boundaries, with independently current
-- observations (not a cached global approval across callbacks).
theorem location_then_reader_current
    (location metadata readerSupport : List Node)
    (before located readerEntry : Node → Nat)
    (locationCovered : ∀ node, node ∈ location → node ∈ metadata)
    (metadataCurrent : ∀ node, node ∈ metadata → before node = located node)
    (fullEntry : ∀ node, node ∈ readerSupport → before node = readerEntry node) :
    (∀ node, node ∈ location → before node = located node) ∧
    (∀ node, node ∈ readerSupport → before node = readerEntry node) := by
  exact ⟨covered_guard_preserves_currentness location metadata before located
           locationCovered metadataCurrent, fullEntry⟩

theorem omitted_support_can_escape [DecidableEq Node]
    (checked : List Node) (missing : Node) (absent : missing ∉ checked) :
    ∃ before now : Node → Nat,
      (∀ node, node ∈ checked → before node = now node) ∧
      before missing ≠ now missing := by
  refine ⟨fun _ => 0, fun node => if node = missing then 1 else 0, ?_, ?_⟩
  · intro node member
    have different : node ≠ missing := by
      intro same
      exact absent (same ▸ member)
    simp [different]
  · simp

-- Coverage is necessary, not merely sufficient, when a guard promises
-- currentness for EVERY possible source revision. Runtime import discovery
-- alone does not establish coverage of an initializer's ambient effects.
theorem universally_sound_guard_iff_coverage [DecidableEq Node]
    (required checked : List Node) :
    (∀ before now : Node → Nat,
      (∀ node, node ∈ checked → before node = now node) →
      ∀ node, node ∈ required → before node = now node) ↔
    (∀ node, node ∈ required → node ∈ checked) := by
  constructor
  · intro sound node demanded
    by_cases member : node ∈ checked
    · exact member
    · obtain ⟨before, now, current, changed⟩ := omitted_support_can_escape checked node member
      exact False.elim (changed (sound before now current node demanded))
  · intro coverage before now current
    exact covered_guard_preserves_currentness required checked before now coverage current

-- A certified operation's cost is its real support width. The theorem does
-- not manufacture the certification from runtime import edges or object names.
def operationReads (widths : List Nat) : Nat := widths.sum

theorem bounded_operation_support (widths : List Nat) (bound : Nat)
    (bounded : ∀ width ∈ widths, width ≤ bound) :
    operationReads widths ≤ bound * widths.length := by
  induction widths with
  | nil => simp [operationReads]
  | cons width rest ih =>
    have head := bounded width (by simp)
    have tail := ih (fun value member => bounded value (by simp [member]))
    simp only [operationReads, List.sum_cons, List.length_cons, Nat.mul_succ] at *
    omega

-- Local admission is not Graph visibility. Commit checks ALL selected support
-- independently of the earlier candidate revision, including a source which
-- changed only after local admission. No confinement of arbitrary IO is assumed.
theorem candidate_commit_current
    (selected finalChecked : List Node) (before commit : Node → Nat)
    (complete : ∀ node, node ∈ selected → node ∈ finalChecked)
    (freshCommit : ∀ node, node ∈ finalChecked → before node = commit node) :
    ∀ node, node ∈ selected → before node = commit node :=
  covered_guard_preserves_currentness selected finalChecked before commit complete freshCommit

-- Projection must preserve every actual requirement. Once that correspondence
-- is established, changes outside semantic support cannot make its guard fail.
-- This does not infer non-escape or purity for arbitrary initializer objects.
theorem scratch_outside_support_preserves_guard
    (support : List Node) (before initialized now : Node → Nat)
    (checked : ∀ node, node ∈ support → before node = initialized node)
    (stable : ∀ node, node ∈ support → initialized node = now node) :
    ∀ node, node ∈ support → before node = now node := by
  intro node required
  exact (checked node required).trans (stable node required)

theorem failed_candidate_keeps_previous {Value : Type} (previous candidate : Value) :
    (if false then candidate else previous) = previous := rfl

-- Count real support widths, not the accumulated publication prefix. Open
-- callbacks retain their independently charged full work; no linear bound is
-- claimed for N open callbacks each of which depends on the complete Graph.
def stagedGuardReads (widths : List Nat) (fullPasses selectedWidth openWork : Nat) : Nat :=
  operationReads widths + fullPasses * selectedWidth + openWork

theorem staged_guard_bound (widths : List Nat) (bound fullPasses selectedWidth openWork : Nat)
    (bounded : ∀ width ∈ widths, width ≤ bound) :
    stagedGuardReads widths fullPasses selectedWidth openWork ≤
      bound * widths.length + fullPasses * selectedWidth + openWork := by
  have localWork := bounded_operation_support widths bound bounded
  unfold stagedGuardReads
  omega

-- A cached directory hit must re-enroll its path observations. Splitting the
-- root/decision/path supports cannot omit negative competing-path lookups.
-- Quint explores when they change; this lemma requires ACTUAL coverage and
-- current observations at this boundary, not a previous successful approval.
theorem candidate_location_support_current
    (required root decision path : List Node) (before now : Node → Nat)
    (coverage : ∀ node, node ∈ required → node ∈ (root ++ decision) ++ path)
    (rootCurrent : ∀ node, node ∈ root → before node = now node)
    (decisionCurrent : ∀ node, node ∈ decision → before node = now node)
    (pathCurrent : ∀ node, node ∈ path → before node = now node) :
    ∀ node, node ∈ required → before node = now node := by
  intro node demanded
  have present := coverage node demanded
  simp only [List.mem_append] at present
  rcases present with (inRoot | inDecision) | inPath
  · exact rootCurrent node inRoot
  · exact decisionCurrent node inDecision
  · exact pathCurrent node inPath

-- The reader already indexes immutable Gerbil runtime closures. Registration into
-- its existing source map belongs to the miss, not to every later demand.
-- Fresh source admission is charged separately and never memoized by this law.
def enrollmentWork [DecidableEq Node] (width : Node → Nat) :
    List Node → List Node → Nat
  | [], _ => 0
  | root :: rest, seen =>
      if root ∈ seen then enrollmentWork width rest seen
      else width root + enrollmentWork width rest (root :: seen)

def demandedWork (width : Node → Nat) (roots : List Node) : Nat :=
  (roots.map width).sum

def newlyEnrolled [DecidableEq Node] : List Node → List Node → List Node
  | [], _ => []
  | root :: rest, seen =>
      if root ∈ seen then newlyEnrolled rest seen
      else root :: newlyEnrolled rest (root :: seen)

theorem enrollment_covers_demands [DecidableEq Node] (roots seen : List Node) :
    ∀ root ∈ roots, root ∈ seen ∨ root ∈ newlyEnrolled roots seen := by
  induction roots generalizing seen with
  | nil => simp
  | cons first rest ih =>
    intro root present
    by_cases hit : first ∈ seen
    · simp only [newlyEnrolled, hit, ite_eq_left]
      rcases List.mem_cons.mp present with same | tail
      · exact Or.inl (same ▸ hit)
      · exact ih seen root tail
    · simp only [newlyEnrolled, hit, ite_false]
      rcases List.mem_cons.mp present with same | tail
      · exact Or.inr (List.mem_cons.mpr (Or.inl same))
      · rcases ih (first :: seen) root tail with old | fresh
        · rcases List.mem_cons.mp old with same | old
          · exact Or.inr (List.mem_cons.mpr (Or.inl same))
          · exact Or.inl old
        · exact Or.inr (List.mem_cons_of_mem first fresh)

theorem enrollment_preserves_source_support [DecidableEq Node]
    (closure : Node → List Source) (roots seen : List Node)
    (observations : List Source)
    (old : ∀ root ∈ seen, ∀ source ∈ closure root, source ∈ observations)
    (fresh : ∀ root ∈ newlyEnrolled roots seen,
      ∀ source ∈ closure root, source ∈ observations) :
    ∀ root ∈ roots, ∀ source ∈ closure root, source ∈ observations := by
  intro root demanded source required
  rcases enrollment_covers_demands roots seen root demanded with known | added
  · exact old root known source required
  · exact fresh root added source required

theorem enrollment_bounded_by_demands [DecidableEq Node]
    (width : Node → Nat) (roots seen : List Node) :
    enrollmentWork width roots seen ≤ demandedWork width roots := by
  induction roots generalizing seen with
  | nil => simp [enrollmentWork, demandedWork]
  | cons root rest ih =>
    by_cases hit : root ∈ seen
    · simp only [enrollmentWork, hit, ite_eq_left, demandedWork, List.map_cons, List.sum_cons]
      have h := ih seen
      unfold demandedWork at h
      omega
    · simpa [enrollmentWork, hit, demandedWork] using
        Nat.add_le_add_left (ih (root :: seen)) (width root)

theorem enrolled_repeat_has_no_registration_work [DecidableEq Node]
    (width : Node → Nat) (root : Node) (count : Nat) (seen : List Node)
    (hit : root ∈ seen) :
    enrollmentWork width (List.replicate count root) seen = 0 := by
  induction count with
  | zero => simp [enrollmentWork]
  | succ count ih => simpa [List.replicate_succ, enrollmentWork, hit] using ih

theorem repeated_root_enrolled_once [DecidableEq Node]
    (width : Node → Nat) (root : Node) (count : Nat) :
    enrollmentWork width (List.replicate (count + 1) root) [] = width root := by
  simp only [List.replicate_succ, enrollmentWork, List.not_mem_nil, ite_false]
  rw [enrolled_repeat_has_no_registration_work width root count [root] (by simp)]
  omega

theorem repeated_root_still_admitted_on_every_demand
    (width : Node → Nat) (root : Node) (count : Nat) :
    demandedWork width (List.replicate count root) = count * width root := by
  induction count with
  | zero => simp [demandedWork]
  | succ count ih =>
    simpa [List.replicate_succ, demandedWork, Nat.succ_mul, Nat.add_comm] using
      congrArg (fun n => width root + n) ih

-- DFS vertex/edge work is only ONE term. Runtime parsing, expansion, repeated
-- token edges (including predicate-internal replay) and GC need independent
-- receipts. No previous source-read bound establishes this weighted budget.

-- Functional abstraction of make-module-interface: its consumer receives the
-- public validator's actual result, never the pre-check constructor candidate.
-- Option models refusal only; this is not a second runtime evidence protocol.
def inspectChecked (check : Value → Option Checked) (candidate : Value)
    (inspect : Checked → Result) : Option Result :=
  (check candidate).map inspect

theorem refused_profile_cannot_reach_inspection
    (check : Value → Option Checked) (candidate : Value)
    (inspect : Checked → Result) (refused : check candidate = none) :
    inspectChecked check candidate inspect = none := by
  simp [inspectChecked, refused]

theorem inspection_receives_actual_checked_profile
    (check : Value → Option Checked) (candidate : Value) (checked : Checked)
    (inspect : Checked → Result) (accepted : check candidate = some checked) :
    inspectChecked check candidate inspect = some (inspect checked) := by
  simp [inspectChecked, accepted]

-- Checked-value normalization need NOT be idempotent. The staged path has one
-- boundary check; retaining the public validated constructor as an implicit
-- default would normalize twice. No arbitrary callback-equivalence is claimed.
theorem normalization_is_not_implicitly_idempotent :
    inspectChecked (fun n : Nat => some (n + 1)) 0 id = some 1 ∧
    inspectChecked (fun n : Nat => some (n + 1)) 1 id = some 2 := by
  decide

-- Pure replay work for a common constructor trace of width k, reached on
-- every boundary. Construction cost and actual per-boundary checking remain
-- independently charged; source bytes and open callbacks are not removed.
theorem constructor_trace_replay_removed (modules boundaries constructor localWidth : Nat) :
    modules * boundaries * (constructor + localWidth) =
      modules * boundaries * localWidth + modules * boundaries * constructor := by
  rw [Nat.mul_add]
  omega

-- Unlike Quint's finite hook schedules, this law quantifies over any returned
-- value and callback. The predicate is assumed to represent the actual return
-- check; neither purity of Scheme observers nor MOP confinement is proved here.
def checkCallbackReturn (valid : Value → Bool) (callback : Value → Value)
    (candidate : Value) : Option Value :=
  let returned := callback candidate
  if valid returned then some returned else none

theorem callback_return_is_checked (valid : Value → Bool)
    (callback : Value → Value) (candidate returned : Value)
    (accepted : checkCallbackReturn valid callback candidate = some returned) :
    valid returned = true := by
  dsimp only [checkCallbackReturn] at accepted
  split at accepted
  next current =>
    have identity := Option.some.inj accepted
    simpa [identity] using current
  next => contradiction

theorem construction_check_cannot_replace_callback_return_check :
    (0 == (0 : Nat)) = true ∧
    checkCallbackReturn (fun n : Nat => n == 0) (fun _ => 1) 0 = none := by
  decide

-- Functional staging, not memoized validation: each demand runs its check.
-- The closed path has no consumer before this check. The open path supplies
-- the actual checked value to the hook, then checks that hook's return anew.
def admitCarrierCandidate (check : Value → Option Value)
    (hook : Option (Value → Value)) (candidate : Value) : Option Value :=
  (check candidate).bind fun checked =>
    match hook with
    | none => some checked
    | some callback => check (callback checked)

theorem closed_carrier_admission_is_one_check
    (check : Value → Option Value) (candidate : Value) :
    admitCarrierCandidate check none candidate = check candidate := by
  simp [admitCarrierCandidate]

theorem refused_carrier_cannot_reach_hook
    (check : Value → Option Value) (candidate : Value) (hook : Value → Value)
    (refused : check candidate = none) :
    admitCarrierCandidate check (some hook) candidate = none := by
  simp [admitCarrierCandidate, refused]

theorem hook_receives_checked_carrier_and_return_is_rechecked
    (check : Value → Option Value) (candidate checked : Value) (hook : Value → Value)
    (accepted : check candidate = some checked) :
    admitCarrierCandidate check (some hook) candidate = check (hook checked) := by
  simp [admitCarrierCandidate, accepted]

-- Only the eliminated recursive-check component is charged. No claim about
-- runtime read replay, allocation, interpreter expansion or total capacity.
theorem closed_carrier_recursive_check_work (demands width : Nat) :
    demands * (width + width) = demands * width + demands * width := by
  exact Nat.mul_add demands width width

-- Private literal field rows lower to the same left-to-right short circuit.
-- Machine can include a runtime observer trace and arbitrary getter/predicate
-- effects. Only creation of the static predicate list/cut wrappers is omitted;
-- no purity assumption is made for the actual field operation below.
def evalFieldRows {Key Machine : Type} (step : Key → Machine → Bool × Machine) :
    List Key → Machine → Bool × Machine
  | [], state => (true, state)
  | item :: rest, state =>
    let result := step item state
    if result.1 then evalFieldRows step rest result.2 else result

def lowerFieldRows {Key Machine : Type} (step : Key → Machine → Bool × Machine)
    (keys : List Key) : Machine → Bool × Machine :=
  keys.foldr (fun item next state =>
    let result := step item state
    if result.1 then next result.2 else result) (fun state => (true, state))

theorem lowering_preserves_effectful_field_order {Key Machine : Type}
    (step : Key → Machine → Bool × Machine) (keys : List Key) :
    lowerFieldRows step keys = evalFieldRows step keys := by
  induction keys with
  | nil => rfl
  | cons item rest ih =>
    funext state
    change (let result := step item state
            if result.1 then lowerFieldRows step rest result.2 else result) = _
    rw [ih]
    rfl

structure DeclarationCost where
  preparation : Nat
  expansion : Nat
  initialization : Nat
  admission : Nat
  replay : Nat
  sourceGuards : Nat
  collection : Nat

def DeclarationCost.total (cost : DeclarationCost) : Nat :=
  cost.preparation + cost.expansion + cost.initialization + cost.admission +
    cost.replay + cost.sourceGuards + cost.collection

theorem linear_work_does_not_establish_capacity :
    1000 * 700000 > 600000000 := by decide
-- Above is a counterexample in abstract microsecond charges, NOT a measured
-- machine-time claim. Even linear 0.7-second declarations exceed 600 seconds.

/-! Source correspondence for `module-system/graph/funs.ss:module-closure`.
The Scheme loop keeps sibling tails as frames instead of copying a flattened
queue. The list below models the ordered identities in its hash set; it is NOT
the implementation of hash lookup, nor a constant-time lookup assumption. -/
namespace Frames

structure State (Node : Type) where
  seen : List Node
  frames : List (List Node)
  exhausted : Nat

def project (s : State Node) : Discovery Node := ⟨s.seen, s.frames.flatten⟩

def next [DecidableEq Node] (deps : Node → List Node) (s : State Node) : State Node :=
  match s.frames with
  | [] => s
  | [] :: rest => ⟨s.seen, rest, s.exhausted + 1⟩
  | (node :: siblings) :: rest =>
    if node ∈ s.seen then ⟨s.seen, siblings :: rest, s.exhausted⟩
    else ⟨node :: s.seen, deps node :: siblings :: rest, s.exhausted⟩

theorem empty_frame_is_stutter [DecidableEq Node] (deps : Node → List Node)
    (seen : List Node) (rest : List (List Node)) (pops : Nat) :
    project (next deps ⟨seen, [] :: rest, pops⟩) =
      project (⟨seen, [] :: rest, pops⟩ : State Node) := by
  simp [next, project]

theorem nonempty_frame_refines_advance [DecidableEq Node] (deps : Node → List Node)
    (seen : List Node) (node : Node) (siblings : List Node)
    (rest : List (List Node)) (pops : Nat) :
    project (next deps ⟨seen, (node :: siblings) :: rest, pops⟩) =
      advance deps (project ⟨seen, (node :: siblings) :: rest, pops⟩) := by
  by_cases visited : node ∈ seen <;>
    simp [next, project, advance, visited]

-- One initial root frame; exactly one new frame for each first expansion.
-- Hence housekeeping does not hide another scan of every selected module.
def Balanced (s : State Node) : Prop :=
  s.exhausted + s.frames.length = s.seen.length + 1

theorem next_balanced [DecidableEq Node] (deps : Node → List Node)
    (s : State Node) (h : Balanced s) : Balanced (next deps s) := by
  rcases s with ⟨seen, frames, pops⟩
  cases frames with
  | nil => exact h
  | cons siblings rest =>
    cases siblings with
    | nil => simpa [Balanced, next, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using h
    | cons node siblings =>
      by_cases visited : node ∈ seen
      · simpa [Balanced, next, visited] using h
      · simp only [Balanced, List.length_cons] at h ⊢
        simp [next, visited, List.length_cons]
        omega

def run [DecidableEq Node] (deps : Node → List Node) : Nat → State Node → State Node
  | 0, s => s
  | fuel + 1, s => run deps fuel (next deps s)

theorem run_balanced [DecidableEq Node] (deps : Node → List Node)
    (fuel : Nat) (s : State Node) (h : Balanced s) : Balanced (run deps fuel s) := by
  induction fuel generalizing s with
  | zero => exact h
  | succ fuel ih => exact ih _ (next_balanced deps s h)

theorem exhausted_frames_bound [DecidableEq Node] (deps : Node → List Node)
    (roots : List Node) (fuel : Nat) :
    (run deps fuel ⟨[], [roots], 0⟩).exhausted ≤
      (run deps fuel ⟨[], [roots], 0⟩).seen.length + 1 := by
  have h := run_balanced deps fuel ⟨[], [roots], 0⟩ (by simp [Balanced])
  unfold Balanced at h
  omega

end Frames

end YuanxuProof.ModuleSystem.Graph.SourceClosureWork
