// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// epoch is a proposed write-boundary assumption, NOT current runtime behavior.
module RouteMutationModel {
  const BUG: str
  type State = {phase: int, writes: bool, miss: bool, a: bool, b: bool,
    route: int, generation: int, events: int, calls: int, receiverRevision: int,
    accepted: bool, parentPort: int, childPort: int, planOwner: int,
    unselected: int, cache: Set[int]}
  var s: State
  action init = {
    nondet writes = Set(false, true).oneOf()
    nondet miss = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, writes: writes, miss: miss, a: a, b: b,
      route: 0, generation: 0, events: 0, calls: 0, receiverRevision: 0,
      accepted: false, parentPort: 5432, childPort: 5433, planOwner: 2,
      unselected: 0, cache: Set(1)}}
  }
  action bindChild = all {s.phase == 0,
    s' = s.with("phase", 1)
      .with("cache", if (s.miss) s.cache else s.cache.union(Set(2)))
      .with("unselected", if (BUG == "eager") 1 else 0)}
  // Callback edits a raw wrapper/backend route, not the POO receiver.
  action edit = all {s.phase == 1,
    s' = s.with("phase", 2).with("route", if (s.writes) 1 else 0)
      .with("events", if (s.writes) 1 else 0)
      .with("generation", if (s.writes and BUG != "untracked") 1 else 0)}
  action invoke = all {s.phase == 2,
    s' = s.with("phase", 3).with("calls", if (s.writes) 1 else 0)}
  action restore = all {s.phase == 3,
    s' = s.with("phase", 4).with("route", 0)
      .with("generation", if (s.writes and BUG != "untracked") 2 else s.generation)}
  action finish = all {s.phase == 4,
    s' = s.with("phase", 5).with("accepted",
      s.route == 0 and s.receiverRevision == 0 and
      (BUG == "endpoint" or s.generation == 0) and s.a and (s.b or BUG == "dropB"))
      .with("planOwner", if (BUG == "parent") 1 else 2)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {bindChild, edit, invoke, restore, finish, terminal}
  val NoRouteWritesAtReturn = not(s.accepted) or s.events == 0
  val NoForeignEffectsAtReturn = not(s.accepted) or s.calls == 0
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val ParentIsolated = s.parentPort == 5432 and s.childPort == 5433
  val LazyBranch = s.unselected == 0
  val MissNotCached = not(s.miss) or not(s.cache.contains(2))
  val ReceiverRevisionUnchanged = s.receiverRevision == 0
  val RejectAll = not(s.accepted)
  val safety = NoRouteWritesAtReturn and NoForeignEffectsAtReturn and BothRequirements
    and ChildPlan and ParentIsolated and LazyBranch and MissNotCached
    and ReceiverRevisionUnchanged
}
module RouteMutation { import RouteMutationModel(BUG = "none").* }
