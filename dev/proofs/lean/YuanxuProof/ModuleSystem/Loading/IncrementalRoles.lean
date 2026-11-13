-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Loading.MetadataProjection
import YuanxuProof.ModuleSystem.Graph.TestAdmission

namespace YuanxuProof.ModuleSystem.Loading.IncrementalRoles
open LeanPoo.Functional

-- Keys denote role identity, not just a module name. Instantiate compile-import
-- and value-read closure separately; neither relation denotes execution order.
inductive Dirty (reads : Key → List Key) (changed : Key → Prop) : Key → Prop
  | source {key} : changed key → Dirty reads changed key
  | consumer {key dependency} : dependency ∈ reads key →
      Dirty reads changed dependency → Dirty reads changed key

theorem cleanSource {reads : Key → List Key} {changed : Key → Prop} {key : Key}
    (clean : ¬ Dirty reads changed key) : ¬ changed key :=
  fun modified => clean (.source modified)

theorem cleanDependency {reads : Key → List Key} {changed : Key → Prop} {key dep : Key}
    (clean : ¬ Dirty reads changed key) (edge : dep ∈ reads key) :
    ¬ Dirty reads changed dep := fun dirty => clean (.consumer edge dirty)

/-- Runtime invalidation is receiver-granular. Each actual read edge must be
registered in the same direction: consumer depends on provider. Shared slots on
one receiver may conservatively invalidate together; slot-minimality is not claimed. -/
inductive Affected {Receiver : Type} (registered : Receiver → Receiver → Prop)
    (changed : Receiver → Prop) : Receiver → Prop
  | source {owner} : changed owner → Affected registered changed owner
  | consumer {owner provider} : registered owner provider →
      Affected registered changed provider → Affected registered changed owner

/-- Completeness of registration suffices for no missed invalidation, on any
finite path. It does not prove extraction completeness from an arbitrary hook. -/
theorem readDirtyProjects {Key Receiver : Type} (reads : Key → List Key)
    (changed : Key → Prop) (owner : Key → Receiver)
    (registered : Receiver → Receiver → Prop)
    (coverage : ∀ key dep, dep ∈ reads key →
      owner key = owner dep ∨ registered (owner key) (owner dep))
    {key : Key} (dirty : Dirty reads changed key) :
    Affected registered (fun receiver => ∃ source, changed source ∧ owner source = receiver)
      (owner key) := by
  induction dirty with
  | source modified => exact .source ⟨_, modified, rfl⟩
  | @consumer key dependency edge _ ih =>
    rcases coverage key dependency edge with same | registeredEdge
    · rw [same]
      exact ih
    · exact .consumer registeredEdge ih

/-- Derived from the actual read graph, never a separately maintained list.
Same-receiver edges need no enrollment: runtime invalidation clears the owner. -/
def RegisteredRead {Key Receiver : Type} (reads : Key → List Key)
    (owner : Key → Receiver) (consumer provider : Receiver) : Prop :=
  consumer ≠ provider ∧ ∃ key dep,
    owner key = consumer ∧ owner dep = provider ∧ dep ∈ reads key

theorem extractedRegistrationComplete {Key Receiver : Type}
    (reads : Key → List Key) (owner : Key → Receiver) (key dep : Key)
    (edge : dep ∈ reads key) :
    owner key = owner dep ∨ RegisteredRead reads owner (owner key) (owner dep) := by
  by_cases same : owner key = owner dep
  · exact Or.inl same
  · exact Or.inr ⟨same, key, dep, rfl, rfl, edge⟩

theorem actualReadInvalidates {Key Receiver : Type} (reads : Key → List Key)
    (changed : Key → Prop) (owner : Key → Receiver) {key : Key}
    (dirty : Dirty reads changed key) :
    Affected (RegisteredRead reads owner)
      (fun receiver => ∃ source, changed source ∧ owner source = receiver) (owner key) :=
  readDirtyProjects reads changed owner (RegisteredRead reads owner)
    (extractedRegistrationComplete reads owner) dirty

/-- Native with-slot-dependencies enrolls the getter owner against all distinct
receivers in its captured issued dependency closure, not only immediate edges.
The caller must be the actual getter owner; issuer traversal must be complete. -/
def CapturedRegistration {Key Receiver : Type} (reads : Key → List Key)
    (owner : Key → Receiver) (consumer provider : Receiver) : Prop :=
  consumer ≠ provider ∧ ∃ key dependency,
    owner key = consumer ∧ owner dependency = provider ∧
      Graph.TestAdmission.Demanded reads (reads key) dependency

private theorem direct_owner_affected {Key Receiver : Type}
    (reads : Key → List Key) (owner : Key → Receiver) (changed : Receiver → Prop)
    (key dependency : Key) (edge : dependency ∈ reads key)
    (dirty : Affected (RegisteredRead reads owner) changed (owner dependency)) :
    Affected (RegisteredRead reads owner) changed (owner key) := by
  rcases extractedRegistrationComplete reads owner key dependency edge with same | registered
  · rw [same]
    exact dirty
  · exact .consumer registered dirty

private theorem captured_owner_affected {Key Receiver : Type}
    (reads : Key → List Key) (owner : Key → Receiver) (changed : Receiver → Prop)
    (key dependency : Key)
    (captured : Graph.TestAdmission.Demanded reads (reads key) dependency)
    (dirty : Affected (RegisteredRead reads owner) changed (owner dependency)) :
    Affected (RegisteredRead reads owner) changed (owner key) := by
  induction captured with
  | root dependency member => exact direct_owner_affected reads owner changed key dependency member dirty
  | dependency parent child _ edge ih =>
    exact ih (direct_owner_affected reads owner changed parent child edge dirty)

/-- Additional captured transitive edges preserve the affected receiver set.
This is no assertion that their physical edge count or retained bytes is minimal. -/
theorem captured_registration_same_affected_receivers {Key Receiver : Type}
    (reads : Key → List Key) (owner : Key → Receiver) (changed : Receiver → Prop)
    (receiver : Receiver) :
    Affected (CapturedRegistration reads owner) changed receiver ↔
      Affected (RegisteredRead reads owner) changed receiver := by
  constructor
  · intro affected
    induction affected with
    | source modified => exact .source modified
    | consumer captured _ ih =>
      rcases captured with ⟨_, key, dependency, consumerOwner, providerOwner, demand⟩
      rw [← consumerOwner]
      apply captured_owner_affected reads owner changed key dependency demand
      simpa [providerOwner] using ih
  · intro affected
    induction affected with
    | source modified => exact .source modified
    | consumer registered _ ih =>
      rcases registered with ⟨different, key, dependency, consumerOwner, providerOwner, edge⟩
      exact .consumer ⟨different, key, dependency, consumerOwner, providerOwner,
        .root dependency edge⟩ ih

/-- Projection of the runtime final clear loop, after its checked identity DFS.
The traversal itself and absence of concurrent writes remain correspondence obligations. -/
def clearSelected {Receiver Value : Type} [DecidableEq Receiver]
    (selected : List Receiver) (before : Receiver → Option Value) (owner : Receiver) :
    Option Value := if owner ∈ selected then none else before owner

theorem unrelatedRetained {Receiver Value : Type} [DecidableEq Receiver]
    (registered : Receiver → Receiver → Prop) (changed : Receiver → Prop)
    (selected : List Receiver) (before : Receiver → Option Value)
    (onlyAffected : ∀ owner ∈ selected, Affected registered changed owner)
    (owner : Receiver) (unrelated : ¬ Affected registered changed owner) :
    clearSelected selected before owner = before owner := by
  have notSelected : owner ∉ selected := fun member => unrelated (onlyAffected owner member)
  simp [clearSelected, notSelected]

/-- Unchanged resolver code alone does not prove unchanged dependent values. -/
theorem unchangedResolver {Key : Type} {Value : Key → Type} {Policy : Type}
    [DecidableEq Key] (request : GeneralizedMOP.Request Key Value Policy)
    (edits : List (GeneralizedMOP.Redefinition Key Value Policy)) (key : Key)
    (clean : ConstructionCache.changed edits key = false)
    (state : GeneralizedGraph.State Key Value) :
    (GeneralizedMOP.redefine request edits).graph.resolve key state =
      request.graph.resolve key state :=
  ConstructionCache.redefine_unchanged request edits key clean state

/-- Locality and exact input agreement are required. An author purity flag or
unchanged procedure pointer is insufficient for arbitrary effectful Scheme. -/
theorem unchangedValue {Key Value Result : Type} (reads : Key → List Key)
    (old new : Key → (Key → Value) → Result) (before after : Key → Value) (key : Key)
    (sameCode : new key = old key)
    (locality : ∀ a b, (∀ dep ∈ reads key, a dep = b dep) → old key a = old key b)
    (sameInputs : ∀ dep ∈ reads key, before dep = after dep) :
    new key after = old key before := by
  rw [sameCode]
  exact (locality before after sameInputs).symm

/-- Immutable closed data may be shared; external authentication must rerun. -/
theorem retainClosed {Key : Type} {Value : Key → Type} [DecidableEq Key]
    {spec : GeneralizedGraph.Declaration Key Value}
    (cache : ConstructionCache.Cache spec) (order : List Key) :
    (cache.retain order).closed = cache.closed ∧
    (cache.retain order).evaluated = [] :=
  ⟨ConstructionCache.Cache.retain_closed cache order,
    (ConstructionCache.Cache.retain_work cache order).1⟩

/-- A source stamp covers the declaration bytes. A retained value can also
close over the selection context passed to admission. -/
theorem sameSourceNotEnough :
    ∃ (factory : Bool → Bool) (oldSource newSource : Nat)
      (oldSelection newSelection : Bool),
      oldSource = newSource ∧ factory oldSelection ≠ factory newSelection := by
  exact ⟨id, 0, 0, false, true, rfl, Bool.noConfusion⟩

/-- The payload proof and the fresh admission check are separate obligations.
A reusable result does not transfer the authority of its old selection. -/
theorem freshEdgeAdmission {Source : Type} {old checked live : Source}
    (fresh : checked = live) (provider consumer : Prop)
    (approved : provider ∧ consumer) (stale : old ≠ live) :
    checked ≠ old ∧ provider ∧ consumer := by
  exact ⟨fun same => stale (same.symm.trans fresh), approved⟩

/-- Identical native support and identical constructor code still allow a
different result when the constructor closes over a mutable Scheme cell. -/
theorem recordedSupportDoesNotImplyLocality :
    ∃ (build : Unit → Bool → Bool) (oldHidden newHidden : Bool),
      build () oldHidden ≠ build () newHidden := by
  exact ⟨fun _ hidden => hidden, false, true, Bool.noConfusion⟩

/-- The lowered constructor receives an ordered list of role values. Each
position must carry the same value identity and the same provider authority.
The source check is separate because a live identity can outlast its source. -/
structure RoleInput (ValueId Authority Revision : Type) where
  identity : ValueId
  authority : Authority
  revision : Revision

theorem constrainedRoleConstruction
    {ValueId Authority Revision Result : Type}
    (build : List (RoleInput ValueId Authority Revision) → Result)
    (before after : List (RoleInput ValueId Authority Revision))
    (sameInputs : ∀ index : Nat, before[index]? = after[index]?) :
    build before = build after :=
  congrArg build (List.ext_getElem? sameInputs)

/-- Exact source and authority agreement does not imply resolved role identity
agreement. Gerbil may evaluate a new private role context for the same bytes. -/
theorem roleRevisionDoesNotDetermineIdentity :
    ∃ before after : RoleInput Bool Unit Nat,
      before.revision = after.revision ∧ before.authority = after.authority ∧
      before.identity ≠ after.identity := by
  exact ⟨⟨false, (), 0⟩, ⟨true, (), 0⟩, rfl, rfl, Bool.noConfusion⟩

/-- A stable role does not make newly allocated checking wrappers identical.
Payload equality and Scheme's `eq?` are separate proof obligations. -/
theorem normalizationAllocationNotIdentity
    {Payload Stamp : Type} (value : Payload) (before after : Stamp)
    (fresh : before ≠ after) : (value, before) ≠ (value, after) := by
  intro same
  exact fresh (congrArg Prod.snd same)

/-- A checked field can be retained only when its own policy is still current.
The normalized receiver is retained only after all field checks have returned
their inputs. The graph's separate admission decision can still refuse it. -/
theorem checkedRoleIdentityAndFreshAdmission
    {Field Policy : Type}
    (fields : List (Field × Policy)) (live : Policy → Policy)
    (normalize : Field → Policy → Field)
    (current : ∀ entry ∈ fields, live entry.2 = entry.2)
    (stable : ∀ entry ∈ fields, normalize entry.1 entry.2 = entry.1)
    (approve : List Field → Bool) (refused : approve (fields.map Prod.fst) = false) :
    let checked := fields.map fun entry => normalize entry.1 (live entry.2)
    checked = fields.map Prod.fst ∧ approve checked = false := by
  dsimp
  have same : (fields.map fun entry => normalize entry.1 (live entry.2)) =
      fields.map Prod.fst := by
    apply List.map_congr_left
    intro entry member
    rw [current entry member, stable entry member]
  exact ⟨same, same ▸ refused⟩

open Graph.TestAdmission in
theorem reverse_index_reaches_exactly_affected {Owner : Type}
    (consumers : Owner → List Owner) (registered : Owner → Owner → Prop)
    (exactIndex : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed : List Owner) (owner : Owner) :
    Demanded consumers changed owner ↔ Affected registered (fun k => k ∈ changed) owner := by
  constructor
  · intro reached
    induction reached with
    | root _ member => exact .source member
    | dependency provider consumer _ edge ih =>
      exact .consumer ((exactIndex provider consumer).mp edge) ih
  · intro affected
    induction affected with
    | source member => exact .root _ member
    | consumer edge _ ih => exact .dependency _ _ ih ((exactIndex _ _).mpr edge)

open Graph.TestAdmission in
/-- Read the existing reverse index from the changed roots, then point-check
which reached owners belong to the retained certificate. No catalog scan. -/
def recheckOwners (consumers : Nat → List Nat) (changed : List Nat) (fuel : Nat)
    (retained : Nat → Bool) : List Nat :=
  (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.seen.filter retained

open Graph.TestAdmission in
theorem recheck_owners_exact (consumers : Nat → List Nat) (registered : Nat → Nat → Prop)
    (exactIndex : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed : List Nat) (fuel : Nat) (retained : Nat → Bool)
    (complete : (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.pending = [])
    (owner : Nat) :
    owner ∈ recheckOwners consumers changed fuel retained ↔
      Affected registered (fun k => k ∈ changed) owner ∧ retained owner = true := by
  simp only [recheckOwners, List.mem_filter]
  rw [completed_indexed_discovery_exact consumers changed fuel complete owner,
    reverse_index_reaches_exactly_affected consumers registered exactIndex changed owner]

open Graph.TestAdmission in
/-- An interrupted reverse walk cannot approve a certificate, even when every
owner in the partial trace has passed. -/
def repairIndexed (state : IndexedDiscovery) (retained verify : Nat → Bool) : Bool :=
  state.ordered.pending.isEmpty && (state.ordered.seen.filter retained).all verify

open Graph.TestAdmission in
theorem repair_requires_complete_walk (state : IndexedDiscovery)
    (retained verify : Nat → Bool) :
    repairIndexed state retained verify = true ↔
      state.ordered.pending = [] ∧
      ∀ owner ∈ state.ordered.seen, retained owner = true → verify owner = true := by
  simp only [repairIndexed, Bool.and_eq_true, List.isEmpty_iff, List.all_eq_true,
    List.mem_filter, and_imp]

open Graph.TestAdmission in
/-- Certificate repair has the same result as checking every retained owner,
provided unchanged support keeps clean owners valid. Newly reachable owners
are handled by forward admission, outside this repair of retained evidence. -/
theorem recheck_preserves_certificate (consumers : Nat → List Nat)
    (registered : Nat → Nat → Prop)
    (exactIndex : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed : List Nat) (fuel : Nat) (retained before verify : Nat → Bool)
    (complete : (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.pending = [])
    (prior : ∀ owner, retained owner = true → before owner = true)
    (stable : ∀ owner, retained owner = true →
      ¬ Affected registered (fun k => k ∈ changed) owner → verify owner = before owner) :
    repairIndexed (discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩) retained verify = true ↔
      ∀ owner, retained owner = true → verify owner = true := by
  change ((discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩).ordered.pending.isEmpty &&
    (recheckOwners consumers changed fuel retained).all verify) = true ↔ _
  simp only [complete, List.isEmpty_nil, Bool.true_and, List.all_eq_true]
  constructor
  · intro repaired owner retainedOwner
    by_cases dirty : Affected registered (fun k => k ∈ changed) owner
    · exact repaired owner ((recheck_owners_exact consumers registered exactIndex changed fuel
        retained complete owner).mpr ⟨dirty, retainedOwner⟩)
    · rw [stable owner retainedOwner dirty, prior owner retainedOwner]
  · intro verified owner member
    exact verified owner ((recheck_owners_exact consumers registered exactIndex changed fuel
      retained complete owner).mp member).2

open Graph.TestAdmission in
/-- A 10,000-owner certificate with a three-owner affected component.
The other 9,997 owners require no repair call. -/
theorem ten_thousand_owner_local_recheck :
    recheckOwners (fun owner => if owner = 11 then [12] else if owner = 12 then [13] else [])
      [11] 3 (fun owner => owner < 10000) = [13, 12, 11] := by
  unfold recheckOwners
  rw [discover_indexed_refines _ _ _ (empty_discovery_index_exact [11])]
  decide

open Graph.TestAdmission in
/-- A retained clean owner is a boundary of the forward walk. The new graph
still determines reachability; a removed edge supplies no scope authority. -/
def editDependencies (next : Nat → List Nat) (reusable : Nat → Bool) (owner : Nat) :
    List Nat :=
  if reusable owner then [] else next owner

open Graph.TestAdmission in
theorem edit_forward_reaches_every_uncertified_owner
    (next : Nat → List Nat) (reusable : Nat → Bool)
    (closed : ∀ owner, reusable owner = true →
      ∀ child ∈ next owner, reusable child = true)
    (roots : List Nat) (owner : Nat) (needed : Demanded next roots owner) :
    Demanded (editDependencies next reusable) roots owner ∨ reusable owner = true := by
  induction needed with
  | root owner member => exact Or.inl (.root owner member)
  | dependency parent child _ edge ih =>
    cases h : reusable parent with
    | true => exact Or.inr (closed parent h child edge)
    | false =>
      rcases ih with walked | impossible
      · exact Or.inl (.dependency parent child walked (by simpa [editDependencies, h] using edge))
      · simp [h] at impossible

/-- Clean reuse is forward-closed when old evidence was closed, clean
owners kept their edges, and the old reverse index covers those edges. -/
theorem clean_edit_boundary_closed (old next : Nat → List Nat)
    (registered : Nat → Nat → Prop) (changed : List Nat) (retained : Nat → Prop)
    (oldClosed : ∀ owner, retained owner → ∀ child ∈ old owner, retained child)
    (registration : ∀ owner child, child ∈ old owner → owner = child ∨ registered owner child)
    (unchanged : ∀ owner, ¬ Affected registered (fun k => k ∈ changed) owner →
      next owner = old owner)
    (owner : Nat) (kept : retained owner)
    (clean : ¬ Affected registered (fun k => k ∈ changed) owner)
    (child : Nat) (edge : child ∈ next owner) :
    retained child ∧ ¬ Affected registered (fun k => k ∈ changed) child := by
  rw [unchanged owner clean] at edge
  refine ⟨oldClosed owner kept child edge, ?_⟩
  intro dirty
  rcases registration owner child edge with same | registeredEdge
  · exact clean (same.symm ▸ dirty)
  · exact clean (.consumer registeredEdge dirty)

open Graph.TestAdmission in
/-- Publishing is a single gate. Live entry/return checks are supplied by the
effect boundary, separately from discovery and the existing POO evidence. -/
def publishDependencyEdit (reverse forward : IndexedDiscovery)
    (reusable known verify : Nat → Bool)
    (entryOK returnOK : Bool) : Bool :=
  entryOK && reverse.ordered.pending.isEmpty &&
    admitIndexed forward known (fun owner => reusable owner || verify owner) && returnOK

open Graph.TestAdmission in
theorem dependency_edit_publication_checks
    (reverse forward : IndexedDiscovery) (reusable known verify : Nat → Bool)
    (entryOK returnOK : Bool)
    (published : publishDependencyEdit reverse forward reusable known verify
      entryOK returnOK = true) :
    entryOK = true ∧ returnOK = true ∧ reverse.ordered.pending = [] ∧
      forward.ordered.pending = [] := by
  simp only [publishDependencyEdit, Bool.and_eq_true] at published
  exact ⟨published.1.1.1, published.2,
    List.isEmpty_iff.mp published.1.1.2,
    by
      have complete := published.1.2
      simp only [admitIndexed, Bool.and_eq_true, List.isEmpty_iff] at complete
      exact complete.1⟩

open Graph.TestAdmission in
theorem dependency_edit_admits_new_owner
    (reverse : IndexedDiscovery) (next : Nat → List Nat)
    (roots : List Nat) (fuel : Nat) (reusable known verify : Nat → Bool)
    (entryOK returnOK : Bool)
    (closed : ∀ owner, reusable owner = true →
      ∀ child ∈ next owner, reusable child = true)
    (published : publishDependencyEdit reverse
      (discoverIndexed (editDependencies next reusable) fuel ⟨⟨[], roots⟩, ∅⟩)
      reusable known verify entryOK returnOK = true)
    (owner : Nat) (needed : Demanded next roots owner) (fresh : reusable owner = false) :
    known owner = true ∧ verify owner = true := by
  have checks := dependency_edit_publication_checks _ _ _ _ _ _ _ published
  have reached : Demanded (editDependencies next reusable) roots owner := by
    rcases edit_forward_reaches_every_uncertified_owner next reusable closed roots owner needed
      with reached | kept
    · exact reached
    · simp [fresh] at kept
  simp only [publishDependencyEdit, Bool.and_eq_true] at published
  have verified := (indexed_admission_boundary (editDependencies next reusable) roots fuel known
    (fun k => reusable k || verify k) checks.2.2.2).mp published.1.2 owner reached
  simpa [fresh] using verified

open Graph.TestAdmission in
theorem failed_new_admission_blocks_edit
    (reverse : IndexedDiscovery) (next : Nat → List Nat)
    (roots : List Nat) (fuel : Nat) (reusable known verify : Nat → Bool)
    (entryOK returnOK : Bool)
    (closed : ∀ owner, reusable owner = true → ∀ child ∈ next owner, reusable child = true)
    (owner : Nat) (needed : Demanded next roots owner)
    (fresh : reusable owner = false) (failure : verify owner = false) :
    publishDependencyEdit reverse
      (discoverIndexed (editDependencies next reusable) fuel ⟨⟨[], roots⟩, ∅⟩)
      reusable known verify entryOK returnOK = false := by
  cases result : publishDependencyEdit reverse
      (discoverIndexed (editDependencies next reusable) fuel ⟨⟨[], roots⟩, ∅⟩)
      reusable known verify entryOK returnOK with
  | false => rfl
  | true =>
    have passed := (dependency_edit_admits_new_owner reverse next roots fuel reusable known
      verify entryOK returnOK closed result owner needed fresh).2
    simp [failure] at passed

open Graph.TestAdmission in
/-- Recheck affected retained owners and admit new demands with one visited
index. Membership tests apply to the reverse result, never to the roster. -/
def editRoots (reverse : IndexedDiscovery) (retained : Nat → Bool)
    (requested : List Nat) : List Nat :=
  reverse.ordered.seen.filter retained ++ requested

open Graph.TestAdmission in
theorem dependency_edit_rechecks_old_consumer
    (consumers next : Nat → List Nat) (registered : Nat → Nat → Prop)
    (exactIndex : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed requested : List Nat) (reverseFuel forwardFuel : Nat)
    (retained reusable known verify : Nat → Bool) (entryOK returnOK : Bool)
    (owner : Nat) (dirty : Affected registered (fun k => k ∈ changed) owner)
    (previous : retained owner = true) (invalidated : reusable owner = false)
    (closed : ∀ owner, reusable owner = true → ∀ child ∈ next owner, reusable child = true)
    (published :
      let reverse := discoverIndexed consumers reverseFuel ⟨⟨[], changed⟩, ∅⟩
      let forward := discoverIndexed (editDependencies next reusable) forwardFuel
        ⟨⟨[], editRoots reverse retained requested⟩, ∅⟩
      publishDependencyEdit reverse forward reusable known verify entryOK returnOK = true) :
    known owner = true ∧ verify owner = true := by
  dsimp only at published
  have complete := (dependency_edit_publication_checks _ _ _ _ _ _ _ published).2.2.1
  have reached := (recheck_owners_exact consumers registered exactIndex changed reverseFuel
    retained complete owner).mpr ⟨dirty, previous⟩
  have root : owner ∈ editRoots
      (discoverIndexed consumers reverseFuel ⟨⟨[], changed⟩, ∅⟩) retained requested :=
    List.mem_append_left _ reached
  exact dependency_edit_admits_new_owner _ next _ forwardFuel reusable known verify
    entryOK returnOK closed published owner (.root owner root) invalidated

/-- Old evidence for an affected owner is unavailable as soon as invalidation
starts. This rule does not depend on whether replacement later succeeds. -/
def oldCertificateUsable (reverseComplete affected retained : Bool) : Bool :=
  reverseComplete && !affected && retained

theorem affected_old_certificate_is_unusable (complete retained : Bool) :
    oldCertificateUsable complete true retained = false := by
  simp [oldCertificateUsable]

theorem incomplete_invalidation_cannot_use_old_certificate (affected retained : Bool) :
    oldCertificateUsable false affected retained = false := rfl

open Graph.TestAdmission in
theorem old_index_blocks_affected_certificate (consumers : Nat → List Nat)
    (registered : Nat → Nat → Prop)
    (exactIndex : ∀ provider consumer, consumer ∈ consumers provider ↔ registered consumer provider)
    (changed : List Nat) (fuel : Nat) (owner : Nat) (retained : Bool)
    (dirty : Affected registered (fun k => k ∈ changed) owner) :
    let reverse := discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩
    oldCertificateUsable reverse.ordered.pending.isEmpty (reverse.visited.contains owner)
      retained = false := by
  dsimp only
  let reverse := discoverIndexed consumers fuel ⟨⟨[], changed⟩, ∅⟩
  change oldCertificateUsable reverse.ordered.pending.isEmpty (reverse.visited.contains owner)
    retained = false
  cases complete : reverse.ordered.pending with
  | nil =>
    have reached := (reverse_index_reaches_exactly_affected consumers registered exactIndex
      changed owner).mpr dirty
    have member : owner ∈ reverse.ordered.seen :=
      (completed_indexed_discovery_exact consumers changed fuel complete owner).mpr reached
    have indexed : reverse.Exact :=
      discover_indexed_keeps_exact consumers fuel _ (empty_discovery_index_exact changed)
    have present : reverse.visited.contains owner = true :=
      Std.HashSet.mem_iff_contains.mp ((indexed owner).mpr member)
    simp [oldCertificateUsable, present]
  | cons head tail => simp [oldCertificateUsable]

open Graph.TestAdmission in
/-- Scope authority follows the new graph from the original public roots.
Repair seeds do not become new public roots. -/
def EditedScopeAuthorized (published : Bool) (next : Nat → List Nat)
    (publicRoots : List Nat) (owner : Nat) : Prop :=
  published = true ∧ Demanded next publicRoots owner

open Graph.TestAdmission in
theorem removed_unreachable_owner_has_no_authority
    (published : Bool) (next : Nat → List Nat) (roots : List Nat) (owner : Nat)
    (removed : ¬ Demanded next roots owner) :
    ¬ EditedScopeAuthorized published next roots owner :=
  fun access => removed access.2

open Graph.TestAdmission in
/-- Old edges are 13 → 12 → 11 → 10. Only owner 11 changes.
Owner 10 remains clean, but the edit supplies no path to it from 13. -/
private def dependencyEditScale : Bool :=
  let oldConsumers := fun owner =>
    if owner = 10 then [11] else if owner = 11 then [12] else if owner = 12 then [13] else []
  let reverse := discoverIndexed oldConsumers 3 ⟨⟨[], [11]⟩, ∅⟩
  let retained := fun owner => owner < 10000 && owner != 9000
  let reusable := fun owner => retained owner && !reverse.visited.contains owner
  let roots := editRoots reverse retained []
  let next := fun replacement owner =>
    if owner = 13 then [12] else if owner = 12 then [11] else
    if owner = 11 then replacement else []
  let run := fun replacement fuel =>
    discoverIndexed (editDependencies (next replacement) reusable) fuel ⟨⟨[], roots⟩, ∅⟩
  let deleted := run [] 5
  let replaced := run [9000] 6
  let known := fun owner => owner < 10000
  let publish := fun work verify => publishDependencyEdit reverse work reusable known verify true true
  reverse.ordered.seen == [13, 12, 11] &&
    deleted.ordered.seen == [11, 12, 13] && publish deleted (fun _ => true) &&
    replaced.ordered.seen == [9000, 11, 12, 13] && publish replaced (fun _ => true) &&
    !publish replaced (fun owner => owner != 9000) &&
    !(oldCertificateUsable reverse.ordered.pending.isEmpty (reverse.visited.contains 13) true) &&
    !(publishDependencyEdit reverse replaced reusable known (fun _ => true) true false)

#guard dependencyEditScale

/-- The predecessor input index originally combined two disjoint native key
spaces. Transfer visits only the original Gerbil Context keys, in walk order. -/
theorem role_transfer_input_projection
    {Context InputKey Input Origin : Type}
    (contextInput : Context → Option Input) (inputOrigin : InputKey → Option Origin)
    (walk : List Context) :
    walk.map (fun context =>
      (Sum.elim (fun key => (contextInput key).map Sum.inl)
        (fun key => (inputOrigin key).map Sum.inr) (Sum.inl context) :
          Option (Sum Input Origin))) =
      walk.map (fun context => (contextInput context).map Sum.inl) := rfl

/-- With the same ordered Context rows, the same receiving authority runs the
same handoff. Initializer and source guards remain in the original rows. -/
theorem role_transfer_preserves_handoff
    {Context Row Result : Type} (walk : List Context)
    (fromSession fromRoleTables : Context → Row)
    (same : ∀ context ∈ walk, fromSession context = fromRoleTables context)
    (handoff : List Row → Result) :
    handoff (walk.map fromSession) = handoff (walk.map fromRoleTables) := by
  exact congrArg handoff (List.map_congr_left same)

end YuanxuProof.ModuleSystem.Loading.IncrementalRoles
