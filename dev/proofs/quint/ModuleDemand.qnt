// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Architectural model, NOT a model of physical heap bytes or current Scheme.
module ModuleDemandModel {
  const BUG: str
  val selected = Set(1, 2, 3, 4)
  val catalogue = selected.union(Set(5, 6))
  // Both demanded sets are dependency-closed. The unused catalogue may contain
  // an unrelated cycle; the existing graph solver owns selected-cycle refusal.
  val narrow = Set(2, 4)
  val wide = selected
  val tokens = List(21, 41, 21, 42)
  var s: {phase: int, demand: Set[int], shape: int, closed: bool, disabled: bool,
    a: bool, b: bool, selectedRev: int, sourceRev: int,
    descriptorValid: bool, preflightOK: bool, types: Set[int], metadata: Set[int], heavy: Set[int], roleWork: int, selectedOK: bool,
    issued: List[int], observed: List[int], admitted: bool,
    published: bool, parent: int, child: int}
  action init = {
    nondet demand = Set(narrow, wide).oneOf()
    // 0=direct literal declaration; 1=computed dependency; 2=inherited
    // metadata; 3=extra top form; 4=duplicate field. The Scheme decoder
    // must produce this classification from source, never a purity flag.
    nondet shape = Set(0, 1, 2, 3, 4).oneOf()
    val closed = shape == 0
    nondet descriptorValid = Set(false, true).oneOf()
    nondet disabled = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, demand: demand, shape: shape, closed: closed, disabled: disabled,
      descriptorValid: descriptorValid, preflightOK: false, types: Set(),
      a: a, b: b, selectedRev: 0, sourceRev: 0, metadata: Set(), heavy: Set(),
      roleWork: 0, selectedOK: false, issued: List(), observed: List(), admitted: false,
      published: false, parent: 5432, child: 5433}}
  }
  // The closed grammar is still a correspondence obligation of the actual decoder.
  // Opaque policies take the full original path; no capacity promise for them.
  action selectMetadata = {
    val eligible = not(s.disabled) or BUG == "disabled"
    val fallback = eligible and not(s.closed) and BUG != "opaque"
    val loaded = fallback or BUG == "eager"
    all {s.phase == 0,
      s' = s.with("phase", 1).with("closed", s.closed or BUG == "classifier").with("metadata", selected)
        .with("selectedOK", eligible)
        .with("heavy", if (loaded) selected else Set())
        .with("roleWork", if (loaded) 3 * selected.size() else 0)
        .with("issued", if (loaded) tokens else List())
        .with("observed", if (loaded) tokens else List())
        .with("admitted", BUG == "premature")}
  }
  action changeBefore = {
    nondet changed = Set(false, true).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2)
      .with("sourceRev", if (changed) 1 else 0)}
  }
  // Publication validates real Type descriptors before a scope can activate.
  // Types are demanded here; Config, Objects and the link body remain cold.
  action preflight = all {s.phase == 2,
    s' = s.with("phase", 7).with("types", if (s.selectedOK) s.demand else Set())
      .with("preflightOK", s.selectedOK and (s.descriptorValid or BUG == "invalid-contract"))
      .with("heavy", if (BUG == "preflight-eager") s.demand else s.heavy)
      .with("roleWork", if (BUG == "preflight-eager") 3 * s.demand.size() else s.roleWork)
      .with("issued", if (BUG == "preflight-eager") tokens else s.issued)
      .with("observed", if (BUG == "preflight-eager") tokens else s.observed)}
  action activate = {
    val current = s.sourceRev == s.selectedRev or BUG == "stale"
    val modulesEnabled = not(s.disabled) or BUG == "disabled"
    val allowed = if (s.closed or BUG == "opaque") s.demand else selected
    all {s.phase == 7,
      s' = if (s.preflightOK and current and modulesEnabled)
        s.with("phase", 3).with("heavy", allowed)
          .with("roleWork", 3 * allowed.size())
          .with("issued", if (BUG == "edge") List(21, 41, 42) else tokens)
          .with("observed", if (BUG == "observer") List(21, 41, 42) else tokens)
          .with("parent", if (BUG == "parent") 5433 else s.parent)
      else s.with("phase", 3)}
  }
  action admit = all {s.phase == 3,
    s' = s.with("phase", 4).with("admitted",
      s.preflightOK and s.roleWork > 0 and
      (s.sourceRev == s.selectedRev or BUG == "stale") and
      s.a and (s.b or BUG == "dropB"))}
  action changeAfter = {
    nondet changed = Set(false, true).oneOf()
    all {s.phase == 4, s' = s.with("phase", 5)
      .with("sourceRev", if (changed) 2 else s.sourceRev)}
  }
  action publish = all {s.phase == 5,
    s' = s.with("phase", 6).with("published", s.admitted and
      (s.sourceRev == s.selectedRev or BUG == "stale"))}
  action terminal = all {s.phase == 6, s' = s}
  action step = any {selectMetadata, changeBefore, preflight, activate, admit, changeAfter, publish, terminal}
  val ValidPublication = not(s.preflightOK) or s.descriptorValid
  val PreflightOnly = s.phase != 7 or not(s.closed) or
    (s.heavy == Set() and not(s.admitted) and
      s.types == (if (s.selectedOK) s.demand else Set()))
  val Classification = s.closed == (s.shape == 0)
  val DeclarationOnly = s.phase != 1 or not(s.closed) or
    (s.heavy == Set() and not(s.admitted))
  val AdmissionPhase = not(s.admitted) or s.phase >= 4
  val DemandBound = s.heavy.subseteq(if (s.closed) s.demand else selected)
  val NoUnselected = s.metadata.subseteq(catalogue) and s.heavy.subseteq(selected)
  val RoleWork = s.roleWork == 3 * s.heavy.size()
  val ActualTrace = s.roleWork == 0 or (s.issued == tokens and s.observed == tokens)
  val Fresh = not(s.published) or s.sourceRev == s.selectedRev
  val Enabled = (not(s.selectedOK) and s.roleWork == 0) or not(s.disabled)
  val Both = not(s.admitted) or (s.a and s.b)
  val OpaqueCoverage = not(s.published) or s.closed or s.heavy == selected
  val ParentIsolation = s.parent == 5432 and s.child == 5433
  val NoPublication = not(s.published)
  val safety = ValidPublication and PreflightOnly and Classification and DeclarationOnly and AdmissionPhase and DemandBound and NoUnselected and RoleWork and
    ActualTrace and Fresh and Enabled and Both and OpaqueCoverage and ParentIsolation
}
module ModuleDemand { import ModuleDemandModel(BUG = "none").* }
