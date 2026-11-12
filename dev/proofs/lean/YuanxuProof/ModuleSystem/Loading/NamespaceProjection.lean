-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Loading.ManagedBinding
import YuanxuProof.ModuleSystem.Graph.TestAdmission

/-! Ordinary POO namespace bindings, not a second Tree/Node runtime or cache.
The native bridge supplies a finite complete key domain and admitted source
bindings. The resolver remains the existing owner of evaluation/admission. -/
namespace YuanxuProof.ModuleSystem.Loading.NamespaceProjection

/-- Window containment does not itself establish a Module owner. The native
bridge supplies an indexed declaration/Interface boundary and eligibility. -/
def sourceAccess (insideKernel moduleBoundary eligible current : Bool) : Bool :=
  insideKernel && (!moduleBoundary || eligible) && current

theorem ordinary_library_crosses_window (current : Bool) :
    sourceAccess true false false current = current := by simp [sourceAccess]

theorem closed_module_cannot_become_library (insideKernel current : Bool) :
    sourceAccess insideKernel true false current = false := by simp [sourceAccess]

theorem source_reclassification_refuses : sourceAccess true false false false = false := rfl

theorem source_access_requires_kernel_and_current (kernel boundary eligible current : Bool)
    (accepted : sourceAccess kernel boundary eligible current = true) :
    kernel = true ∧ current = true := by
  cases kernel <;> cases boundary <;> cases eligible <;> cases current <;>
    simp_all [sourceAccess]

/-- The native bridge supplies the originally observed context/name/path
binding, never a replacement captured after a load-path edit. The compiler
association is scoped to its original dynamic extent and preserves bytes. -/
def publicSourceCurrent (bytes binding compilerAssociation canonicalTarget : Bool) : Bool :=
  bytes && binding && (compilerAssociation || canonicalTarget)

theorem public_source_cannot_retarget (bytes : Bool) :
    publicSourceCurrent bytes true false false = false := by
  simp [publicSourceCurrent]

theorem compiler_association_preserves_binding (bytes compilerAssociation target : Bool) :
    publicSourceCurrent bytes false compilerAssociation target = false := by
  simp [publicSourceCurrent]

theorem public_source_requires_bytes (binding compilerAssociation target : Bool) :
    publicSourceCurrent false binding compilerAssociation target = false := rfl

theorem compiler_bridge_ends_with_consumer :
    publicSourceCurrent true true true false = true ∧
    publicSourceCurrent true true false false = false := by decide

def windowOwnershipQuintDigest : String :=
  "sha256:faecab83aa8a7cc381eb52b7cf105b5e8b31147130339849495482e876fa885e"

abbrev Path := List String
abbrev Bindings := Path → Option Path

/-- Restrict the source target, so a new alias cannot disclose a hidden name. -/
def restrict (visible : Path → Bool) (bindings : Bindings) : Bindings :=
  fun key => (bindings key).filter visible

def names (domain : List Path) (bindings : Bindings) : List Path :=
  domain.filter (fun key => (bindings key).isSome)

/-- Native branch metadata uses symbol names, projected here as one-segment
paths. Nested branches compose native POO getters; no leaf handle is rebuilt. -/
def branchBindings (entries : String → Option String) : Bindings :=
  fun path => match path with
    | [key] => (entries key).map (fun target => [target])
    | _ => none

theorem branch_restrict_target (entries : String → Option String)
    (visible : Path → Bool) (key target : String) (found : entries key = some target) :
    restrict visible (branchBindings entries) [key] =
      if visible [target] then some [target] else none := by
  cases permitted : visible [target] <;> simp [restrict, branchBindings, found, permitted]

/-- A view transports the original handle intact: owner, revision, generation
and dependency metadata remain those of the admitted source catalog. -/
def metadata (catalog : Path → Option ManagedBinding.Handle) (bindings : Bindings)
    (key : Path) : Option ManagedBinding.Handle := (bindings key).bind catalog

theorem metadata_preserves_handle (catalog : Path → Option ManagedBinding.Handle)
    (bindings : Bindings) (key : Path) (handle : ManagedBinding.Handle)
    (found : metadata catalog bindings key = some handle) :
    ∃ target, bindings key = some target ∧ catalog target = some handle := by
  cases origin : bindings key with
  | none => simp [metadata, origin] at found
  | some target => exact ⟨target, rfl, by simpa [metadata, origin] using found⟩

theorem reflection_lookup_agree (domain : List Path) (bindings : Bindings) (key : Path) :
    key ∈ names domain bindings ↔ key ∈ domain ∧ ∃ target, bindings key = some target := by
  simp [names, Option.isSome_iff_exists]

theorem restricted_binding_origin (visible : Path → Bool) (bindings : Bindings)
    (key target : Path) (found : restrict visible bindings key = some target) :
    bindings key = some target ∧ visible target = true := by
  simpa [restrict, Option.filter_eq_some_iff] using found

theorem restriction_idempotent (visible : Path → Bool) (bindings : Bindings) :
    restrict visible (restrict visible bindings) = restrict visible bindings := by
  funext key
  cases source : bindings key with
  | none => simp [restrict, source]
  | some target => cases flag : visible target <;> simp [restrict, source, flag]

theorem hidden_target_has_no_alias (visible : Path → Bool) (bindings : Bindings)
    (key target : Path) (alias : bindings key = some target) (hidden : visible target = false) :
    restrict visible bindings key = none := by simp [restrict, alias, hidden]

/-- The resolver may be effectful; projection returns its SAME result/state.
Opaque values can represent actual Scope references, without copying them. -/
def demand {State Value : Type} (bindings : Bindings) (key : Path)
    (resolve : Path → State → Except String Value × State) (state : State) :
    Except String Value × State :=
  match bindings key with
  | none => (.error "namespace binding unavailable", state)
  | some target => resolve target state

theorem hidden_refuses_without_resolving {State Value : Type}
    (bindings : Bindings) (key : Path)
    (resolve : Path → State → Except String Value × State) (state : State)
    (hidden : bindings key = none) :
    demand bindings key resolve state = (.error "namespace binding unavailable", state) := by
  simp [demand, hidden]

theorem permitted_demand_is_original_operation {State Value : Type}
    (bindings : Bindings) (key target : Path)
    (resolve : Path → State → Except String Value × State) (state : State)
    (alias : bindings key = some target) :
    demand bindings key resolve state = resolve target state := by simp [demand, alias]

theorem aliases_preserve_original_return {State Value : Type}
    (bindings : Bindings) (left right target : Path)
    (resolve : Path → State → Except String Value × State) (state : State)
    (l : bindings left = some target) (r : bindings right = some target) :
    demand bindings left resolve state = demand bindings right resolve state := by
  simp [demand, l, r]

/-- A leaf formula takes the final receiver and a lazy continuation for
one slot. The Interface supplies its explicit dependencies. The public path
belongs to the namespace, so it is absent from the formula's inputs. -/
def leafValue {Receiver Slot Dependencies Value : Type}
    (formula : Receiver → (Unit → Slot) → Dependencies → Value)
    (receiver : Receiver) (inherited : Unit → Slot) (dependencies : Dependencies) : Value :=
  formula receiver inherited dependencies

/-- The trace records only the demanded owner and its explicit dependency
closure. The native bridge provides the admitted owner and exact scope. -/
theorem mounted_leaf_preserves_value_and_demand
    {Receiver Slot Dependencies Value : Type}
    (bindings : Bindings) (left right owner sibling : Path)
    (receiver : Receiver) (inherited : Unit → Slot) (dependencies : Dependencies)
    (formula : Receiver → (Unit → Slot) → Dependencies → Value)
    (closure : List Path) (l : bindings left = some owner)
    (r : bindings right = some owner) (other : sibling ≠ owner)
    (cold : sibling ∉ closure) :
    let resolve := fun key (_ : Unit) =>
      ((Except.ok (leafValue formula receiver inherited dependencies,
        key :: closure) : Except String (Value × List Path)), ())
    demand bindings left resolve () = demand bindings right resolve () ∧
      sibling ∉ owner :: closure := by
  simp [demand, l, r, other, cold]

/-- A selected branch carries suffixes of its original declared paths.
This is a reference relation for native grouped indexes, not another index. -/
def childPaths (key : String) (paths : List Path) : List Path :=
  paths.filterMap (fun path => match path with
    | [] => none
    | head :: tail => if head == key then some tail else none)

theorem child_bucket_exact (key : String) (paths : List Path) (suffix : Path) :
    suffix ∈ childPaths key paths ↔ key :: suffix ∈ paths := by
  simp only [childPaths, List.mem_filterMap]
  constructor
  · rintro ⟨path, present, found⟩
    cases path with
    | nil => simp at found
    | cons head tail =>
      change (if head == key then some tail else none) = some suffix at found
      by_cases same : head = key
      · have tailSame : tail = suffix := by simpa [same] using found
        simpa [same, tailSame] using present
      · simp [same] at found
  · intro present
    exact ⟨key :: suffix, present, by simp⟩

/-- A physical catalog is not the scope demand set. Reuse the existing graph
relation; declaration admission must establish the closed region separately.
This law grants neither source currentness nor compiler authority. -/
theorem scope_demand_stays_in_admitted_catalog {Node : Type}
    (dependencies : Node → List Node) (roots : List Node) (admitted : Node → Prop)
    (rootsAdmitted : ∀ node ∈ roots, admitted node)
    (closed : ∀ node, admitted node → ∀ child ∈ dependencies node, admitted child)
    (node : Node)
    (demanded : Graph.TestAdmission.Demanded dependencies roots node) : admitted node := by
  induction demanded with
  | root node member => exact rootsAdmitted node member
  | dependency parent child _ member ih => exact closed parent ih child member

/-- Finite fixture correspondence only, not native capacity evidence. All
thousand declarations may be admitted while one demand constructs two scopes. -/
def thousandDependencies (node : Nat) : List Nat := if node = 0 then [] else [0]

theorem thousand_catalog_two_scope_demand :
    Graph.TestAdmission.discover thousandDependencies 4 ⟨[], [1]⟩ = ⟨[0, 1], []⟩ := by
  decide

theorem thousand_catalog_closed (node : Nat) (_inside : node < 1000)
    (child : Nat) (member : child ∈ thousandDependencies node) : child < 1000 := by
  by_cases zero : node = 0
  · simp [thousandDependencies, zero] at member
  · simp [thousandDependencies, zero] at member
    omega

/-- Lab consumer init selects Nix under the default modules branch. The
path after that leaf is an ordinary POO slot path, outside namespace routing. -/
def labNixBindings : Bindings
  | ["modules", "nix"] => some ["nix"]
  | _ => none

def labNixPublicSlots : List String :=
  ["config", "types", "prototypes", "source-inputs", "admit-generation"]

theorem lab_nix_consumer_routes_original_scope {State Scope : Type}
    (resolve : Path → State → Except String Scope × State) (state : State) :
    demand labNixBindings ["modules", "nix"] resolve state = resolve ["nix"] state ∧
      "config" ∈ labNixPublicSlots ∧ "prototypes" ∈ labNixPublicSlots := by
  simp [demand, labNixBindings, labNixPublicSlots]

theorem lab_nix_config_is_not_another_module {State Scope : Type}
    (resolve : Path → State → Except String Scope × State) (state : State) :
    demand labNixBindings ["modules", "nix", "config"] resolve state =
      (.error "namespace binding unavailable", state) := rfl

/-- Nix's actual Interface declares an empty requires object. This graph
models Module scopes. Gerbil library imports and compiler products have
their own closure. -/
def labNixRequirements (_owner : Path) : List Path := []

theorem lab_nix_scope_closure :
    Graph.TestAdmission.discover labNixRequirements 2 ⟨[], [["nix"]]⟩ =
      ⟨[["nix"]], []⟩ := by decide

/-- The scale fixture puts all declarations in one public branch. Keep the
index workload and the admission roster distinct from the reached scopes. -/
def thousandBranchPaths : List Path :=
  (List.range 1000).map (fun id => ["modules", "module-" ++ toString id])

theorem thousand_branch_contains_every_fixture_leaf (id : Nat) (inside : id < 1000) :
    ["module-" ++ toString id] ∈ childPaths "modules" thousandBranchPaths := by
  apply (child_bucket_exact "modules" thousandBranchPaths ["module-" ++ toString id]).2
  exact List.mem_map.mpr ⟨id, List.mem_range.mpr inside, rfl⟩

theorem thousand_first_business_scope_accounting :
    (List.range 1000).length = 1000 ∧
    thousandBranchPaths.length = 1000 ∧
    Graph.TestAdmission.discover thousandDependencies 4 ⟨[], [1]⟩ = ⟨[0, 1], []⟩ := by
  simp [thousandBranchPaths, thousand_catalog_two_scope_demand]

/-- A bulk native branch constructor may retain only authorized rows. Its
input is already read and validated in the original metadata order. No
provider is called to derive the row list. -/
def admittedBranchRows (visible : Path → Bool) (rows : List (Path × Path)) :
    List (Path × Path) :=
  rows.filter (fun row => visible row.2)

theorem admitted_branch_rows_exact (visible : Path → Bool)
    (rows : List (Path × Path)) (key target : Path) :
    (key, target) ∈ admittedBranchRows visible rows ↔
      (key, target) ∈ rows ∧ visible target = true := by
  simp [admittedBranchRows]

theorem admitted_branch_rows_no_growth (visible : Path → Bool)
    (rows : List (Path × Path)) :
    (admittedBranchRows visible rows).length ≤ rows.length := by
  exact List.length_filter_le _ _

/-- Fetching a catalog supplies availability, not owner demand. Native package
defaults with no owner roots cannot invent demand, even in a cyclic catalog.
Dependency installation/default build behavior remains a native obligation. -/
theorem empty_default_selects_no_owner {Node : Type} (dependencies : Node → List Node)
    (node : Node) : ¬ Graph.TestAdmission.Demanded dependencies [] node := by
  intro reached
  induction reached with
  | root _ member => simp at member
  | dependency _ _ _ _ ih => exact ih

/-- Native tool correspondence: required indexing follows the unchanged native
dependency/default-build effects. No opt-out; native execution remains external. -/
def packageInstallTrace (required : List String) : List String :=
  required ++ ["editor-tags"]

theorem editor_index_preserves_required_prefix (required : List String) :
    (packageInstallTrace required).take required.length = required := by
  simp [packageInstallTrace]

theorem default_retains_editor_effect (required : List String) :
    packageInstallTrace required = required ++ ["editor-tags"] := by
  rfl

/-- Projection of the native tagger's streaming input partition. `done` is a
proof trace; the native tool does not retain completed expander contexts. -/
structure IndexBatches (Source : Type) where
  done : List (List Source)
  pending : List Source

def indexItems {Source : Type} (state : IndexBatches Source) : List Source :=
  state.done.flatten ++ state.pending

def indexFeed {Source : Type} (width : Nat) (state : IndexBatches Source)
    (source : Source) : IndexBatches Source :=
  if state.pending.length = width then
    ⟨state.done ++ [state.pending], [source]⟩
  else ⟨state.done, state.pending ++ [source]⟩

theorem index_feed_preserves_source_order {Source : Type} (width : Nat)
    (state : IndexBatches Source) (source : Source) :
    indexItems (indexFeed width state source) = indexItems state ++ [source] := by
  simp only [indexFeed]
  split <;> simp [indexItems, List.flatten_append, List.append_assoc]

theorem index_pending_bounded {Source : Type} (width : Nat) (positive : 0 < width)
    (state : IndexBatches Source) (bounded : state.pending.length ≤ width)
    (source : Source) : (indexFeed width state source).pending.length ≤ width := by
  simp only [indexFeed]
  split <;> simp_all <;> omega

/-- Source provenance is a projection of actual loading-window declarations.
Native package/prelude identity is a separate compiler obligation. -/
structure WindowOrigin where
  root : Path
  windows : List Path

def declaredKernel (window : Path) (origins : List WindowOrigin) : Option Path :=
  match origins.filter (fun origin => origin.windows.contains window) with
  | [] => some window
  | [origin] => some origin.root
  | _ => none

theorem no_origin_does_not_widen_window (window : Path) :
    declaredKernel window [] = some window := rfl

theorem declared_window_supplies_kernel (window : Path) (origin : WindowOrigin)
    (declared : window ∈ origin.windows) :
    declaredKernel window [origin] = some origin.root := by
  simp [declaredKernel, declared]

theorem competing_window_origins_refuse (window : Path) (a b : WindowOrigin)
    (left : window ∈ a.windows) (right : window ∈ b.windows) :
    declaredKernel window [a, b] = none := by
  simp [declaredKernel, left, right]

/-- Existing POO declaration slots are addressed by canonical owner, not by
a public alias. Stamps are identities of authenticated inputs, not timestamps
or a substitute for checking the original support. -/
structure DeclarationKey where
  owner : Path
  window : Path
  source : Nat
  policy : Nat
  deriving DecidableEq

/-- Model one read of the owner's existing slot. The retained payload is
declaration data. A successful freshness verdict is never retained. -/
def reuseDeclaration {Declaration : Type} (requested retained : DeclarationKey)
    (payload : Declaration) (support : List Nat) (live : Nat → Bool) :
    Option Declaration :=
  if requested = retained then
    if support.all live then some payload else none
  else none

theorem declaration_slot_hit_exact {Declaration : Type}
    (requested retained : DeclarationKey) (payload : Declaration)
    (support : List Nat) (live : Nat → Bool) :
    reuseDeclaration requested retained payload support live = some payload ↔
      requested = retained ∧ ∀ token ∈ support, live token = true := by
  by_cases same : requested = retained
  · simp [reuseDeclaration, same, List.all_eq_true]
  · simp [reuseDeclaration, same]

theorem declaration_reuse_local_to_support {Declaration : Type}
    (key : DeclarationKey) (payload : Declaration)
    (support : List Nat) (before after : Nat → Bool)
    (stable : ∀ token ∈ support, before token = after token) :
    reuseDeclaration key key payload support before =
      reuseDeclaration key key payload support after := by
  have same : support.all before = support.all after := by
    induction support with
    | nil => rfl
    | cons token tail ih =>
      simp only [List.all_cons]
      rw [stable token (by simp), ih (fun k h => stable k (by simp [h]))]
  simp [reuseDeclaration, same]

theorem declaration_effect_return_rechecks {Declaration : Type}
    (key : DeclarationKey) (payload : Declaration)
    (support : List Nat) (before after : Nat → Bool)
    (entry : reuseDeclaration key key payload support before = some payload)
    (token : Nat) (member : token ∈ support) (changed : after token = false) :
    (reuseDeclaration key key payload support before).isSome = true ∧
      reuseDeclaration key key payload support after = none := by
  have stale : support.all after = false := by
    cases h : support.all after with
    | false => rfl
    | true =>
      have live := (List.all_eq_true.mp h) token member
      simp [changed] at live
  exact ⟨by rw [entry]; rfl, by simp [reuseDeclaration, stale]⟩

section DirectoryOwnerKeys

variable {Owner PathKey Refusal : Type}

/-- A successful callback-free root snapshot can certify an exact direct child.
Every other row still uses its own native filesystem normalization result. -/
structure DirectOwnerKeys (normalize : Owner → Except Refusal PathKey) where
  direct : Owner → Option PathKey
  exact : ∀ owner key, direct owner = some key → normalize owner = .ok key

def ownerKeyFromRoot (normalize : Owner → Except Refusal PathKey)
    (root : Option (DirectOwnerKeys normalize)) (owner : Owner) : Except Refusal PathKey :=
  match root.bind (fun evidence => evidence.direct owner) with
  | none => normalize owner
  | some key => .ok key

theorem owner_key_from_root_exact (normalize : Owner → Except Refusal PathKey)
    (root : Option (DirectOwnerKeys normalize)) (owner : Owner) :
    ownerKeyFromRoot normalize root owner = normalize owner := by
  cases root with
  | none => rfl
  | some evidence =>
    cases found : evidence.direct owner with
    | none => simp [ownerKeyFromRoot, found]
    | some key => simp [ownerKeyFromRoot, found, evidence.exact owner key found]

def ownerRootForWindow {normalize : Owner → Except Refusal PathKey} (enclosing : Bool)
    (root : Option (DirectOwnerKeys normalize)) : Option (DirectOwnerKeys normalize) :=
  if enclosing then none else root

theorem enclosing_window_uses_physical_owner_keys (normalize : Owner → Except Refusal PathKey)
    (root : Option (DirectOwnerKeys normalize)) (owner : Owner) :
    ownerKeyFromRoot normalize (ownerRootForWindow true root) owner = normalize owner := rfl

variable [DecidableEq PathKey]

/-- Path collisions retain the first conflicting declaration in source order,
including owners whose Interface is disabled. -/
def indexOwnerKeys (normalize : Owner → Except Refusal PathKey)
    (duplicate : Owner → Refusal) (seen : List PathKey) : List Owner →
      Except Refusal (List PathKey)
  | [] => .ok seen
  | owner :: rest => (normalize owner).bind fun key =>
    if key ∈ seen then .error (duplicate owner)
    else indexOwnerKeys normalize duplicate (key :: seen) rest

theorem owner_index_from_root_exact (normalize : Owner → Except Refusal PathKey)
    (root : Option (DirectOwnerKeys normalize)) (duplicate : Owner → Refusal)
    (seen : List PathKey) (owners : List Owner) :
    indexOwnerKeys (ownerKeyFromRoot normalize root) duplicate seen owners =
      indexOwnerKeys normalize duplicate seen owners := by
  have exactNormalizer : ownerKeyFromRoot normalize root = normalize :=
    funext (owner_key_from_root_exact normalize root)
  rw [exactNormalizer]

theorem owner_index_stops_at_first_duplicate :
    indexOwnerKeys (fun (_ : Nat) => (.ok 0 : Except Nat Nat)) id [] [1, 2, 3] = .error 2 := rfl

/-- A failed early root probe leaves the original owner pass in front of the
root refusal. An index failure therefore still wins over a root failure. -/
theorem rejected_root_preserves_owner_refusal (normalize : Owner → Except Refusal PathKey)
    (duplicate : Owner → Refusal) (owners : List Owner) (ownerError rootError : Refusal)
    (first : indexOwnerKeys normalize duplicate [] owners = .error ownerError) :
    (indexOwnerKeys (ownerKeyFromRoot normalize none) duplicate [] owners).bind
      (fun _ => (.error rootError : Except Refusal Unit)) = .error ownerError := by
  rw [owner_index_from_root_exact, first]
  rfl

end DirectoryOwnerKeys

section DecisionViews

/-- Identity may already be qualified by the source window. A signed decision
includes a withdrawal. Disabled rows remain indexed as owners. -/
def decisionViews {Row Key : Type} (identity : Row → Key)
    (disabled signed : Row → Bool) : List Row → List Key × List Key × List Key
  | [] => ([], [], [])
  | row :: rest =>
    let (selected, denied, featureRoots) := decisionViews identity disabled signed rest
    if disabled row then (selected, identity row :: denied, featureRoots)
    else (identity row :: selected, denied,
      if signed row then identity row :: featureRoots else featureRoots)

theorem decision_views_exact {Row Key : Type} (identity : Row → Key)
    (disabled signed : Row → Bool) (rows : List Row) :
    decisionViews identity disabled signed rows =
      ((rows.filter (fun row => !disabled row)).map identity,
       (rows.filter disabled).map identity,
       (rows.filter (fun row => !disabled row && signed row)).map identity) := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    cases h : disabled row <;> cases s : signed row <;>
      simp [decisionViews, h, s, ih]

end DecisionViews

section DirectoryPolicy

variable {Check : Type}

/-- A check can represent a path observation or a collision bucket.
The roster is ordered by the reference refusal order. -/
def firstPolicyRefusal (roster : List Check) (accepts : Check → Bool) : Option Check :=
  roster.find? (fun check => !accepts check)

/-- The first pass observes all candidate directory names. Only unchecked
names before the first known link can precede that link's refusal. -/
def directoryLinkCandidates (observed isLink : Check → Bool) : List Check → List Check
  | [] => []
  | name :: rest =>
    if observed name then
      if isLink name then [name] else directoryLinkCandidates observed isLink rest
    else name :: directoryLinkCandidates observed isLink rest

theorem directory_link_refusal_exact (observed isLink : Check → Bool)
    (names : List Check) :
    (directoryLinkCandidates observed isLink names).find? isLink = names.find? isLink := by
  induction names with
  | nil => rfl
  | cons name rest ih =>
    cases known : observed name <;> cases link : isLink name <;>
      simp [directoryLinkCandidates, known, link, ih]

/-- Reusing directory observations and owner keys together preserves the
owner refusal, then the collision refusal, then the first symlink refusal. -/
theorem owner_and_directory_refusals_exact {Owner PathKey Refusal : Type}
    [DecidableEq PathKey] (normalize : Owner → Except Refusal PathKey)
    (root : Option (DirectOwnerKeys normalize)) (duplicate : Owner → Refusal)
    (owners : List Owner) (collision : Option Refusal) (linkError : Check → Refusal)
    (observed isLink : Check → Bool) (names : List Check) :
    let finish (keys : List PathKey) (link : Option Check) : Except Refusal (List PathKey) :=
      match collision, link with
      | some cause, _ => .error cause
      | none, some name => .error (linkError name)
      | none, none => .ok keys
    (indexOwnerKeys (ownerKeyFromRoot normalize root) duplicate [] owners).bind
      (fun keys => finish keys ((directoryLinkCandidates observed isLink names).find? isLink)) =
    (indexOwnerKeys normalize duplicate [] owners).bind
      (fun keys => finish keys (names.find? isLink)) := by
  dsimp only
  rw [owner_index_from_root_exact, directory_link_refusal_exact]

/-- Reuse requires the same observed cut. A link introduced at an independent
effect boundary cannot be authenticated by the original first-pass observation. -/
theorem directory_link_changed_cut_requires_observation :
    (directoryLinkCandidates (fun _ : Nat => true) (fun _ => false) [0]).find?
      (fun _ => true) ≠ ([0] : List Nat).find? (fun _ => true) := by decide

/-- An opaque probe that omits one required check has the same observations
on a fully valid cut and a cut that must refuse. -/
theorem omitted_check_indistinguishable [DecidableEq Check] (roster probed : List Check)
    (missing : Check) (required : missing ∈ roster) (omitted : missing ∉ probed) :
    probed.map (fun _ => true) = probed.map (fun check => decide (check ≠ missing)) ∧
      firstPolicyRefusal roster (fun _ => true) = none ∧
      firstPolicyRefusal roster (fun check => decide (check ≠ missing)) = some missing := by
  constructor
  · induction probed with
    | nil => rfl
    | cons check rest ih =>
      have different : check ≠ missing := fun same => omitted (same ▸ (by simp))
      have restOmitted : missing ∉ rest := fun mem => omitted (by simp [mem])
      have headExact : decide (check ≠ missing) = true := decide_eq_true different
      rw [List.map_cons, List.map_cons, headExact, ih restOmitted]
  constructor
  · simp [firstPolicyRefusal]
  · induction roster with
    | nil => simp at required
    | cons check rest ih =>
      by_cases same : check = missing
      · simp [firstPolicyRefusal, same]
      · have inRest : missing ∈ rest := by
          simpa [Ne.symm same] using required
        simpa [firstPolicyRefusal, same] using ih inRest

theorem no_exact_policy_from_incomplete_probe [DecidableEq Check]
    (roster probed : List Check) (missing : Check)
    (required : missing ∈ roster) (omitted : missing ∉ probed)
    (decideFromProbe : List Bool → Option Check) :
    ¬ ∀ accepts : Check → Bool,
        decideFromProbe (probed.map accepts) = firstPolicyRefusal roster accepts := by
  intro exactDecision
  obtain ⟨same, good, bad⟩ :=
    omitted_check_indistinguishable roster probed missing required omitted
  have accepted := exactDecision (fun _ => true)
  have refused := exactDecision (fun check => decide (check ≠ missing))
  rw [good, same] at accepted
  rw [bad, accepted] at refused
  contradiction

/-- Indexed retrieval may supply an ordered subset directly. Keeping all
failures suffices to preserve the first refusal on the new roster. -/
theorem indexed_first_refusal_exact (candidates roster : List Check)
    (accepts : Check → Bool) (ordered : candidates.Sublist roster)
    (unique : roster.Nodup)
    (covers : ∀ check ∈ roster, accepts check = false → check ∈ candidates) :
    firstPolicyRefusal candidates accepts = firstPolicyRefusal roster accepts := by
  induction ordered with
  | slnil => rfl
  | @cons candidates rest check tail ih =>
    obtain ⟨outside, uniqueRest⟩ := List.nodup_cons.mp unique
    have accepted : accepts check = true := by
      cases current : accepts check with
      | true => rfl
      | false => exact False.elim (outside (tail.subset (covers check (by simp) current)))
    have coversRest : ∀ other ∈ rest, accepts other = false → other ∈ candidates :=
      fun other mem bad => covers other (List.mem_cons_of_mem _ mem) bad
    simpa [firstPolicyRefusal, accepted] using ih uniqueRest coversRest
  | @cons_cons candidates rest check _ ih =>
    obtain ⟨outside, uniqueRest⟩ := List.nodup_cons.mp unique
    have coversRest : ∀ other ∈ rest, accepts other = false → other ∈ candidates := by
      intro other mem bad
      have retained := covers other (List.mem_cons_of_mem _ mem) bad
      have different : other ≠ check := fun same => outside (same ▸ mem)
      simpa [different] using retained
    simp only [firstPolicyRefusal, List.find?_cons]
    rw [← firstPolicyRefusal, ih uniqueRest coversRest]
    rfl

end DirectoryPolicy

end YuanxuProof.ModuleSystem.Loading.NamespaceProjection
