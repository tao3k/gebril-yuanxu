// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Supported writes follow invalidate-state! preflight; raw writes do not.
module ReplayOwnershipModel {
  const BUG: str
  type State = {phase: int, target: str, throws: bool, a: bool, b: bool,
    frames: Set[int], revision: int -> int, effects: int, supported: int,
    denied: bool, rawCalls: int, accepted: bool, parentPort: int,
    childPort: int, planOwner: int, unselected: int}
  var s: State
  action init = {
    nondet target = Set("child", "ancestor", "outer", "delivery", "independent", "none", "raw").oneOf()
    nondet throws = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, target: target, throws: throws, a: a, b: b,
      frames: Set(), revision: Set(1,2,3).mapBy(_ => 0), effects: 0,
      supported: 0, denied: false, rawCalls: 0, accepted: false,
      parentPort: 5432, childPort: 5433, planOwner: 2, unselected: 0}}
  }
  action enter = all {s.phase == 0,
    s' = s.with("phase", 1).with("frames", Set(2))
      .with("unselected", if (BUG == "eager") 1 else 0)}
  // A nested replay keeps the outer frame (owner 2), adds inner owner 3.
  action nested = all {s.phase == 1,
    s' = s.with("phase", 2).with("frames",
      if (s.target == "outer")
        (if (BUG == "dropOuter") Set(3) else s.frames.union(Set(3))) else s.frames)}
  val affected = if (s.target == "ancestor") Set(1,2) else
    if (Set("child","outer","delivery").contains(s.target)) Set(2) else
    if (s.target == "independent") Set(3) else Set()
  // Warm Type catalog delivery/work stays inside the SAME selected frame.
  val blocked = affected.intersect(s.frames).size() > 0 and BUG != "noGuard"
    and not(BUG == "dropDelivery" and s.target == "delivery")
  action attempt = all {s.phase == 2,
    s' = s.with("phase", 3).with("denied", blocked)
      .with("revision", if (not(blocked) or BUG == "partialClear")
        Set(1,2,3).mapBy(owner => if (affected.contains(owner)) s.revision.get(owner) + 1 else s.revision.get(owner))
        else s.revision)
      .with("supported", if (not(blocked) and affected.size() > 0) 1 else 0)
      .with("effects", if (not(blocked) and affected.size() > 0) 1 else 0)
      .with("rawCalls", if (s.target == "raw") 1 else 0)}
  action unwind = all {s.phase == 3,
    s' = s.with("phase", 4).with("frames", if (BUG == "leak" and s.throws) s.frames else Set())}
  action finish = all {s.phase == 4,
    s' = s.with("phase", 5).with("accepted",
      not(s.denied) and not(s.throws) and s.a and (s.b or BUG == "dropB"))
      .with("planOwner", if (BUG == "parent") 1 else 2)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {enter, nested, attempt, unwind, finish, terminal}
  val PreWriteRefusal = s.phase < 3 or
    not(Set("child","ancestor","outer","delivery").contains(s.target)) or s.supported == 0
  val NoPartialClear = not(s.denied) or
    (s.revision.get(1) == 0 and s.revision.get(2) == 0 and s.revision.get(3) == 0)
  val Released = s.phase < 4 or s.frames == Set()
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val ParentCache = s.parentPort == 5432 and s.childPort == 5433
  val LazyBranch = s.unselected == 0
  // Deliberately false: raw SDK mutation is outside this supported-write guard.
  val NoRawCallbacks = not(s.accepted) or s.rawCalls == 0
  val RejectAll = not(s.accepted)
  val safety = PreWriteRefusal and NoPartialClear and Released and BothRequirements
    and ChildPlan and ParentCache and LazyBranch
}
module ReplayOwnership { import ReplayOwnershipModel(BUG = "none").* }
