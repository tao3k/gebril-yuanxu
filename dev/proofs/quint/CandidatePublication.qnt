// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CandidatePublicationModel {
  const BUG: str
  // One Graph, not independent source epochs. A candidate owns its actual
  // role/import/Schema support; unrelated selected support stays at commit.
  pure val selected = Set(0, 1, 2, 3)
  pure val actual = Set(0, 1, 2)
  pure val local = if (BUG == "dropImport") actual.exclude(Set(1)) else actual
  pure def current(dirty: Set[int], support: Set[int]): bool =
    dirty.intersect(support) == Set()
  type State = {phase: int, dirty: Set[int], open: bool, enteredDirty: bool,
    openDirty: bool, returnedDirty: bool, falseRefusal: bool,
    visible: bool, held: bool, previous: int}
  var s: State
  action init = {
    nondet changed = selected.union(Set(-1)).oneOf()
    nondet open = Set(false, true).oneOf()
    s' = {phase: 0, dirty: if (changed == -1) Set() else Set(changed),
      open: open, enteredDirty: false, openDirty: false, returnedDirty: false, falseRefusal: false,
      visible: false, held: true, previous: 1}
  }
  action enter = all { s.phase == 0,
    val allowed = current(s.dirty, local)
    s' = s.with("phase", if (allowed) 1 else 5).with("held", allowed)
      .with("enteredDirty", allowed and not(current(s.dirty, actual)))
  }
  action nativeRoles = {
    nondet changed = selected.union(Set(-1)).oneOf()
    all { s.phase == 1,
      // Node 4 is initializer-local scratch, not an enduring policy or
      // producer requirement. Real SDK construction may invalidate its reads.
      val dirty = if (changed == -1) s.dirty else s.dirty.union(Set(changed))
      s' = s.with("phase", 2).with("dirty", dirty.union(Set(4))) }
  }
  action beforeAdmission = all { s.phase == 2,
    val demanded = if (s.open and BUG != "openBefore") selected else local
    val support = if (BUG == "retainScratch") demanded.union(Set(4)) else demanded
    val allowed = current(s.dirty, support)
    s' = s.with("phase", if (allowed) 3 else 5).with("held", allowed)
      .with("openDirty", s.open and allowed and not(current(s.dirty, selected)))
      .with("falseRefusal", not(allowed) and current(s.dirty, selected))
  }
  action admission = {
    nondet changed = selected.union(Set(-1)).oneOf()
    all { s.phase == 3,
      val dirty = if (changed == -1) s.dirty else s.dirty.union(Set(changed))
      val support = if (s.open and BUG != "openAfter") selected else local
      val allowed = current(dirty, support)
      s' = s.with("phase", if (allowed) 4 else 5).with("dirty", dirty)
        .with("held", allowed)
        .with("returnedDirty", s.open and allowed and not(current(dirty, selected)))
        .with("visible", BUG == "earlyVisible" and allowed) }
  }
  action commit = {
    // A real input may change after local admission. No approval crosses this
    // boundary: selected source support is checked afresh before visibility.
    nondet changed = selected.union(Set(-1)).oneOf()
    all { s.phase == 4,
      val dirty = if (changed == -1) s.dirty else s.dirty.union(Set(changed))
      val support = if (BUG == "dropSchema") selected.exclude(Set(2)) else selected
      val allowed = BUG == "skipCommit" or current(dirty, support)
      s' = s.with("phase", 5).with("dirty", dirty).with("visible", allowed)
        .with("previous", if (allowed) 2 else if (BUG == "replaceOnFailure") 0 else 1)
        .with("held", BUG == "cleanup") }
  }
  action terminate = all { s.phase < 5,
    s' = s.with("phase", 5).with("held", BUG == "cleanup").with("visible", false) }
  action terminal = all { s.phase == 5, s' = s }
  action step = any {enter, nativeRoles, beforeAdmission, admission, commit, terminate, terminal}
  val LocalEntry = not(s.enteredDirty)
  val OpenEntry = not(s.openDirty)
  val OpenReturn = not(s.returnedDirty)
  val FinalCurrent = not(s.visible) or current(s.dirty, selected)
  val CommitOnly = not(s.visible) or s.phase == 5
  val KeepPrevious = s.phase != 5 or s.visible or s.previous == 1
  val Cleanup = s.phase != 5 or not(s.held)
  val NoSpuriousRefusal = not(s.falseRefusal)
  val RejectAll = not(s.visible)
  val safety = LocalEntry and OpenEntry and OpenReturn and FinalCurrent and CommitOnly and KeepPrevious and Cleanup and NoSpuriousRefusal
}
module CandidatePublication {
  import CandidatePublicationModel(BUG = "none").*
}
