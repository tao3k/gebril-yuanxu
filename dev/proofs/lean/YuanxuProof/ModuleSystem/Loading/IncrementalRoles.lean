-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Loading.MetadataProjection

namespace YuanxuProof.ModuleSystem.Loading.IncrementalRoles
open LeanPoo.Functional

def quintSourceDigest : String := "sha256:4d932f9377d21e3b6cd1238d487b0ba9b868fbd325aa69942f948ab26d870261"

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

/-- Native invalidation is receiver-granular. Each actual read edge must be
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
Same-receiver edges need no enrollment: native invalidation clears the owner. -/
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

/-- Projection of the native final clear loop, after its checked identity DFS.
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

end YuanxuProof.ModuleSystem.Loading.IncrementalRoles
