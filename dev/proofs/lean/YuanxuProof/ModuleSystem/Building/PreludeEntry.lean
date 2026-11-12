-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ModuleSystem.Building.Inputs

/-! RFC 13.29 Prelude phase split: a native adapter must extract actual eager
module/phase edges and actual exported bindings. This checks those observations;
it does not implement a lazy loader or certify unobserved macro effects. -/
namespace YuanxuProof.ModuleSystem.Building.PreludeEntry

structure PhaseNode where
  owner : String
  phase : Int
  deriving Repr, DecidableEq

structure Edge where
  consumer : PhaseNode
  provider : PhaseNode
  deriving Repr, DecidableEq

def stratified (rank : PhaseNode → Nat) (edges : List Edge) : Bool :=
  edges.all (fun edge => decide (rank edge.provider < rank edge.consumer))

inductive Path (edges : List Edge) : PhaseNode → PhaseNode → Prop
  | edge (a b : PhaseNode) : Edge.mk a b ∈ edges → Path edges a b
  | extend (a b c : PhaseNode) : Path edges a b → Edge.mk b c ∈ edges → Path edges a c

theorem eager_path_descends (rank : PhaseNode → Nat) (edges : List Edge)
    (checked : stratified rank edges = true) (a b : PhaseNode) (path : Path edges a b) :
    rank b < rank a := by
  have each : ∀ edge ∈ edges, rank edge.provider < rank edge.consumer := by
    simpa [stratified] using checked
  induction path with
  | edge b member => exact each _ member
  | extend b c _ member ih => exact Nat.lt_trans (each _ member) ih

theorem eager_cycle_refused (rank : PhaseNode → Nat) (edges : List Edge)
    (checked : stratified rank edges = true) (node : PhaseNode) : ¬ Path edges node node := by
  intro cycle
  exact Nat.lt_irrefl _ (eager_path_descends rank edges checked node node cycle)

/-- Staged native syntax emits the semantic implementation import into the
consumer Context. It does not add an eager syntax-owner -> implementation edge
to Prelude bootstrap. This is an edge allocation law, not syntax execution. -/
def stageImport (caller implementation : PhaseNode) (edges : List Edge) : List Edge :=
  ⟨caller, implementation⟩ :: edges

theorem staged_import_is_recorded (caller implementation : PhaseNode) (edges : List Edge) :
    Edge.mk caller implementation ∈ stageImport caller implementation edges := by
  simp [stageImport]

theorem staged_import_preserves_stratification (rank : PhaseNode → Nat)
    (edges : List Edge) (caller implementation : PhaseNode)
    (base : stratified rank edges = true) (later : rank implementation < rank caller) :
    stratified rank (stageImport caller implementation edges) = true := by
  simp [stratified, stageImport, later, stratified] at base ⊢
  exact base

structure Binding where
  sourceOwner : String
  sourcePath : String
  name : String
  phase : Int
  reference : Nat
  deriving Repr, DecidableEq

/-- Facade validation compares the complete terminal binding observation, not
just its printed name. Actual weak/strong lookup is supplied by Gerbil. -/
def admitFacade (explicit inherited : Binding) : Option Binding :=
  if explicit = inherited then some inherited else none

theorem admitted_binding_exact (explicit inherited result : Binding)
    (ok : admitFacade explicit inherited = some result) :
    result = explicit ∧ result = inherited := by
  unfold admitFacade at ok
  split at ok
  · rename_i same
    cases ok
    exact ⟨same.symm, rfl⟩
  · contradiction

theorem phase_substitution_refused (explicit inherited : Binding)
    (changed : explicit.phase ≠ inherited.phase) : admitFacade explicit inherited = none := by
  have different : explicit ≠ inherited := fun same => changed (congrArg Binding.phase same)
  simp [admitFacade, different]

theorem reference_substitution_refused (explicit inherited : Binding)
    (changed : explicit.reference ≠ inherited.reference) : admitFacade explicit inherited = none := by
  have different : explicit ≠ inherited := fun same => changed (congrArg Binding.reference same)
  simp [admitFacade, different]

/-- Both language surfaces can feed one pure declaration interpreter only after
binding equality. This conditional theorem does not certify macro hygiene. -/
theorem one_declaration_interpreter {Declaration Result : Type}
    (interpret : Binding → Declaration → Result) (explicit inherited result : Binding)
    (ok : admitFacade explicit inherited = some result) (declaration : Declaration) :
    interpret result declaration = interpret explicit declaration := by
  rw [(admitted_binding_exact explicit inherited result ok).1]

/-- Gerbil-owned invocation context, observed before helper resolution. Terminal
binding identity alone does not preserve where the declaration is expanded. -/
structure Invocation where
  moduleOwner : String
  phase : Int
  lexicalContext : Nat
  marks : List Nat
  source : String
  deriving Repr, DecidableEq

structure HelperResolution where
  helper : Binding
  lookupContext : Invocation
  deriving Repr, DecidableEq

/-- Lookup can use an isolated Gerbil Context. Calling the resolved implementation
must use the original invocation and source origin. Do not manually reapply a
user-macro wrapper or replace syntax with plain data. Native staged macro
expansion introduces its own hygienic marks; terminal binding equivalence must
be established separately rather than assuming identical final mark lists. -/
def handoff {Syntax Result : Type} (expand : Binding → Invocation → Syntax → Result)
    (caller : Invocation) (resolved : HelperResolution) (body : Syntax) : Result :=
  expand resolved.helper caller body

theorem helper_lookup_context_cannot_replace_caller {Syntax Result : Type}
    (expand : Binding → Invocation → Syntax → Result) (caller : Invocation)
    (helper : Binding) (left right : Invocation) (body : Syntax) :
    handoff expand caller ⟨helper, left⟩ body = handoff expand caller ⟨helper, right⟩ body := rfl

theorem handoff_preserves_invocation (caller : Invocation) (resolved : HelperResolution)
    (body : String) :
    handoff (fun _ context body => (context, body)) caller resolved body = (caller, body) := rfl

theorem using_lookup_owner_changes_publication (caller lookup : Invocation)
    (different : caller.moduleOwner ≠ lookup.moduleOwner) :
    (caller.moduleOwner, caller.source) ≠ (lookup.moduleOwner, caller.source) := by
  exact fun same => different (congrArg Prod.fst same)

def kernel : PhaseNode := ⟨"gerbil/core", 0⟩
def syntaxEntry : PhaseNode := ⟨"tao3k/yuanxu/declaration-syntax", 0⟩
def prelude : PhaseNode := ⟨"tao3k/yuanxu/prelude", 0⟩
def implementation : PhaseNode := ⟨"tao3k/yuanxu/module-system", 0⟩

def exampleRank (node : PhaseNode) : Nat :=
  if node = kernel then 0 else if node = syntaxEntry then 1 else if node = prelude then 2 else 3

def splitEdges : List Edge :=
  [⟨syntaxEntry, kernel⟩, ⟨prelude, syntaxEntry⟩, ⟨implementation, prelude⟩]

#guard stratified exampleRank splitEdges
#guard !stratified exampleRank (⟨syntaxEntry, implementation⟩ :: splitEdges)
#guard admitFacade ⟨"syntax", "/syntax.ss", "yuanxu!", 0, 7⟩
  ⟨"syntax", "/syntax.ss", "yuanxu!", 0, 7⟩ = some ⟨"syntax", "/syntax.ss", "yuanxu!", 0, 7⟩
#guard admitFacade ⟨"syntax", "/syntax.ss", "yuanxu!", 0, 7⟩
  ⟨"syntax", "/syntax.ss", "yuanxu!", 1, 7⟩ = none

end YuanxuProof.ModuleSystem.Building.PreludeEntry
