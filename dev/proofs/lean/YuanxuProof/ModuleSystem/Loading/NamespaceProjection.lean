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

end YuanxuProof.ModuleSystem.Loading.NamespaceProjection
