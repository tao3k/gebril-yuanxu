// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Effects are executable transitions, not producer-supplied purity promises.
module ReplayBoundaryModel {
  const BUG: str
  type State = {phase: int, world: int -> int, initial: int -> int,
    tokenRevision: int, issue: int, accepted: bool, bytes: int -> int,
    observed: Set[int], writes: int, visits: Set[int]}
  pure val empty = Set(0, 1, 2).mapBy(_ => -1)
  var s: State
  action init = {
    nondet json = Set(0, 1).oneOf()
    nondet revision = Set(0, 1).oneOf()
    all { s' = {phase: 0, world: empty.set(0, json).set(1, 0),
      initial: empty.set(0, json).set(1, 0), tokenRevision: revision,
      issue: -1, accepted: false, bytes: empty,
      observed: Set(), writes: 0, visits: Set()} }
  }
  action early = all {
    s.phase == 0,
    s' = if (s.world.get(0) != 0 and BUG != "move")
      s.with("phase", 9).with("issue", 0)
    else s.with("phase", 1)
          .with("bytes", if (BUG == "move") s.bytes else s.bytes.set(0, s.world.get(0)))
          .with("observed", if (BUG == "move") s.observed else Set(0))
  }
  action structuralToken = all {
    s.phase == 1,
    s' = if (s.tokenRevision != 0)
      s.with("phase", 9).with("issue", 1)
    else s.with("phase", 2).with("visits", Set(0))
  }
  // Cold precedence preparation can invoke the native compute-precedence hook.
  // It need not happen in the measured cut; no all-producers theorem excludes it.
  action metadata = {
    nondet hookWrite = Set(false, true).oneOf()
    all { s.phase == 2,
      s' = s.with("phase", 3)
            .with("world", if (hookWrite) s.world.set(0, 1) else s.world)
            .with("writes", s.writes + (if (hookWrite) 1 else 0)) }
  }
  action sourceObserver = {
    nondet observerWrite = Set(false, true).oneOf()
    all { s.phase == 3,
      s' = s.with("phase", 4)
            .with("world", if (observerWrite) s.world.set(0, 1) else s.world)
            .with("writes", s.writes + (if (observerWrite) 1 else 0))
            .with("observed", if (BUG == "omit") s.observed else s.observed.union(Set(1))) }
  }
  action finalCheck = {
    val actual0 = if (BUG == "reuse" and s.bytes.get(0) != -1)
                    s.bytes.get(0) else s.world.get(0)
    val issue = if (actual0 != 0) 0 else if (s.world.get(1) != 0) 2 else -1
    all { s.phase == 4,
      s' = s.with("phase", 9).with("issue", issue).with("accepted", issue == -1)
            .with("observed", if (BUG == "omit") s.observed else s.observed.union(Set(0, 1))) }
  }
  action terminal = all { s.phase == 9, s' = s }
  action step = any { early, structuralToken, metadata, sourceObserver, finalCheck, terminal }
  val SourcesCurrent = not(s.accepted) or (s.world.get(0) == 0 and s.world.get(1) == 0)
  val CompleteCoverage = not(s.accepted) or s.observed == Set(0, 1)
  // Fixed message/path codes stand for first-error identity, not rendered text.
  val OrderedDiagnostic = s.phase != 9 or s.writes != 0 or
    s.issue == (if (s.initial.get(0) != 0) 0 else if (s.tokenRevision != 0) 1 else -1)
  val NoEffects = s.writes == 0
  val LazyBranch = s.visits.subseteq(Set(0)) and s.observed.subseteq(Set(0, 1))
  val RejectAll = not(s.accepted)
  val safety = SourcesCurrent and CompleteCoverage and OrderedDiagnostic and LazyBranch
}
module ReplayBoundary {
  import ReplayBoundaryModel(BUG = "none").*
}
