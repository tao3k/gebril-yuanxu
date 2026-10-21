// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module DependencyContinuationModel {
  const BUG: str
  pure val required = Set(0, 1, 2, 3)
  pure val observed = if (BUG == "drop") required.exclude(Set(3)) else required
  pure def current(dirty: Set[int]): bool = dirty.intersect(observed) == Set()
  type State = {phase: int, closed: bool, nextReader: bool, dirty: Set[int],
    openStartedDirty: bool, accepted: bool, held: bool}
  var s: State
  action init = {
    nondet closed = Set(false, true).oneOf()
    nondet nextReader = Set(false, true).oneOf()
    nondet changed = required.union(Set(-1)).oneOf()
    s' = {phase: 0, closed: closed, nextReader: nextReader,
      dirty: if (changed == -1) Set() else Set(changed),
      openStartedDirty: false, accepted: false, held: true}
  }
  // Producer, getters and dependency projection have already returned.
  // Only the paired native candidate can postpone the complete tail guard.
  action completeProducer = all {
    s.phase == 0,
    val allowed = s.closed or BUG == "unseenToken" or current(s.dirty)
    s' = s.with("phase", if (allowed) 1 else 8)
      .with("held", allowed)
      .with("accepted", BUG == "earlyPublish" and allowed)
  }
  // The native continuation walks private symbol lists and hashes. Substituting
  // an open getter here is invalid even if a later full guard would reject it.
  action dependencyWalk = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 1,
      val open = not(s.closed) or BUG == "openWalk"
      s' = s.with("phase", 2)
        .with("openStartedDirty", open and s.dirty.intersect(required) != Set())
        .with("dirty", if (not(open) or changed == -1) s.dirty
          else s.dirty.union(Set(changed))) }
  }
  // Full source support before the next reader's closed location prefix, or
  // before decision/Feature resolution after the complete dependency walk.
  action nextBoundary = all {
    s.phase == 2,
    val skip = (s.nextReader and BUG == "beforeRead") or
      (not(s.nextReader) and BUG == "beforeFeature")
    val allowed = skip or current(s.dirty)
    s' = s.with("phase", if (allowed) 3 else 8).with("held", allowed)
  }
  action openEffect = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 3,
      s' = s.with("phase", 4)
        .with("openStartedDirty", s.openStartedDirty or s.dirty.intersect(required) != Set())
        .with("dirty", if (changed == -1) s.dirty else s.dirty.union(Set(changed))) }
  }
  action finish = all {
    s.phase == 4,
    s' = s.with("phase", 8).with("accepted", current(s.dirty))
      .with("held", BUG == "cleanup")
  }
  action terminate = all {
    s.phase < 8,
    s' = s.with("phase", 8).with("accepted", false).with("held", BUG == "cleanup")
  }
  action terminal = all { s.phase == 8, s' = s }
  action step = any { completeProducer, dependencyWalk, nextBoundary,
    openEffect, finish, terminate, terminal }
  val OpenEntryCurrent = not(s.openStartedDirty)
  val AcceptedOnlyAtEnd = not(s.accepted) or s.phase == 8
  val PublishedCurrent = not(s.accepted) or s.dirty.intersect(required) == Set()
  val Cleanup = s.phase != 8 or not(s.held)
  val RejectAll = not(s.accepted)
  val safety = OpenEntryCurrent and AcceptedOnlyAtEnd and PublishedCurrent and Cleanup
}
module DependencyContinuation {
  import DependencyContinuationModel(BUG = "none").*
}
