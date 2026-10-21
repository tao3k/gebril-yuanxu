// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CandidateLocationModel {
  const BUG: str
  // Root/init, requested decision, positive path, negative competing path.
  // Node 4 belongs only to an earlier, unrelated SourceRef in the SAME Graph.
  pure val actual = Set(0, 1, 2, 3)
  pure val selected = actual.union(Set(4))
  pure def current(dirty: Set[int], support: Set[int]): bool =
    dirty.intersect(support) == Set()
  type State = {phase: int, dirty: Set[int], snapshotHit: bool,
    enteredStale: bool, returnedStale: bool, visible: bool, held: bool, previous: int}
  var s: State
  action init = {
    nondet changed = selected.union(Set(-1)).oneOf()
    nondet hit = Set(false, true).oneOf()
    s' = {phase: 0, dirty: if (changed == -1) Set() else Set(changed),
      snapshotHit: hit, enteredStale: false, returnedStale: false,
      visible: false, held: true, previous: 1}
  }
  pure def demanded(hit: bool): Set[int] =
    if (hit and BUG == "dropCachedPath") Set(0, 1) else actual
  action locate = all {s.phase == 0,
    val allowed = current(s.dirty, demanded(s.snapshotHit))
    s' = s.with("phase", if (allowed) 1 else 3).with("held", allowed)
      .with("enteredStale", allowed and not(current(s.dirty, actual)))
  }
  action nativeRole = {
    nondet changed = selected.union(Set(-1)).oneOf()
    all {s.phase == 1,
      val dirty = if (changed == -1) s.dirty else s.dirty.union(Set(changed))
      val allowed = current(dirty, demanded(s.snapshotHit))
      s' = s.with("phase", if (allowed) 2 else 3).with("dirty", dirty)
        .with("held", allowed)
        .with("returnedStale", allowed and not(current(dirty, actual)))}
  }
  action commit = {
    nondet changed = selected.union(Set(-1)).oneOf()
    all {s.phase == 2,
      val dirty = if (changed == -1) s.dirty else s.dirty.union(Set(changed))
      val allowed = BUG == "skipCommit" or current(dirty, selected)
      s' = s.with("phase", 3).with("dirty", dirty).with("visible", allowed)
        .with("previous", if (allowed) 2 else 1).with("held", false)}
  }
  action terminate = all {s.phase < 3,
    s' = s.with("phase", 3).with("visible", false).with("held", false)}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {locate, nativeRole, commit, terminate, terminal}
  val LocalEntry = not(s.enteredStale)
  val LocalReturn = not(s.returnedStale)
  val FinalCurrent = not(s.visible) or current(s.dirty, selected)
  val KeepPrevious = s.phase != 3 or s.visible or s.previous == 1
  val Cleanup = s.phase != 3 or not(s.held)
  val RejectAll = not(s.visible)
  val safety = LocalEntry and LocalReturn and FinalCurrent and KeepPrevious and Cleanup
}
module CandidateLocation {
  import CandidateLocationModel(BUG = "none").*
}
