// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Isolation gateway only. Raw exported/SDK setters remain reachable counterexamples.
module MetadataOwnershipModel {
  const BUG: str
  type State = {phase: int, path: str, target: str, a: bool, b: bool,
    denied: bool, writes: int, calls: int, route: int, accepted: bool,
    planOwner: int, parentPort: int, childPort: int, unselected: int}
  var s: State
  action init = {
    nondet path = Set("gateway", "generated", "reflective").oneOf()
    nondet target = Set("receiver", "read", "state", "wrapper", "backend", "unknown").oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, path: path, target: target, a: a, b: b,
      denied: false, writes: 0, calls: 0, route: 0, accepted: false,
      planOwner: 2, parentPort: 5432, childPort: 5433, unselected: 0}}
  }
  // Relation comes from genuine selected reads, not a caller-supplied owner.
  val associated = s.target != "unknown" and not(BUG == "omitBackend" and s.target == "backend")
  val blocked = s.path == "gateway" and
    ((associated and BUG != "noGuard") or
     (not(associated) and BUG != "allowUnknown"))
  action replace = all {s.phase == 0,
    s' = s.with("phase", 1).with("denied", blocked)
      .with("writes", if (blocked) 0 else 1)
      .with("route", if (blocked) 0 else 1)
      .with("unselected", if (BUG == "eager") 1 else 0)}
  action invoke = all {s.phase == 1,
    s' = s.with("phase", 2).with("calls", if (s.denied) 0 else 1)}
  action restore = all {s.phase == 2,
    s' = s.with("phase", 3).with("route", 0)
      .with("writes", if (s.denied) s.writes else s.writes + 1)}
  action finish = all {s.phase == 3,
    s' = s.with("phase", 4).with("accepted",
      not(s.denied) and s.a and (s.b or BUG == "dropB"))
      .with("planOwner", if (BUG == "parent") 1 else 2)}
  action terminal = all {s.phase == 4, s' = s}
  action step = any {replace, invoke, restore, finish, terminal}
  val GatewayPreWrite = s.path != "gateway" or (s.writes == 0 and s.calls == 0)
  val UnknownRefused = s.path != "gateway" or s.target != "unknown" or s.writes == 0
  // Coverage is required once association capture has completed, before use.
  val Coverage = s.phase == 0 or s.target == "unknown" or associated
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val ParentCache = s.parentPort == 5432 and s.childPort == 5433
  val LazyBranch = s.unselected == 0
  // False in the normal model: route restoration does not erase callback effects.
  val NoRawCallbacks = not(s.accepted) or s.calls == 0
  val RejectAll = not(s.accepted)
  val safety = GatewayPreWrite and UnknownRefused and Coverage and BothRequirements and ChildPlan and ParentCache and LazyBranch
}
module MetadataOwnership { import MetadataOwnershipModel(BUG = "none").* }
