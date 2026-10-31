// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Constructor events/identity publication, not a second read-graph model.
module ThunkConstructionModel {
  const BUG: str
  var s: {phase: int, kind: str, order: List[int], built: Set[int],
    hooks: List[int], nextFirst: int, nextSecond: int, first: int, second: int}
  val slotKeys = Set(1, 2, 3)
  action init = {
    nondet kind = Set("hook", "reflection", "restricted").oneOf()
    nondet order = Set([1, 2, 3], [3, 1, 2]).oneOf()
    all {s' = {phase: 0, kind: kind, order: order, built: Set(), hooks: [],
      nextFirst: 0, nextSecond: 0, first: 0, second: 0}}
  }
  // restricted is an observation projection, NOT a native purity flag. The
  // existing exported metadata cannot establish it from "no protocol".
  action construct = {
    val delayed = s.kind == "restricted" or
      (BUG == "deferHook" and s.kind == "hook") or
      (BUG == "partialReflect" and s.kind == "reflection")
    all {s.phase == 0, s' = s.with("phase", 1)
      .with("built", if (delayed) Set(3) else slotKeys)
      .with("hooks", if (s.kind != "hook" or delayed) [] else
        if (BUG == "reorder") s.order.foldl([], (xs, n) => [n].concat(xs)) else s.order)
      .with("nextFirst", 31)
      .with("nextSecond", if (BUG == "freshNext" and s.kind == "hook") 32 else 31)}
  }
  action firstRead = all {s.phase == 1,
    s' = s.with("phase", 2).with("first", 31)}
  action secondRead = all {s.phase == 2,
    s' = s.with("phase", 3).with("second", if (BUG == "freshRead") 32 else 31)}
  action done = all {s.phase == 3, s' = s}
  action step = any {construct, firstRead, secondRead, done}
  val HookOrder = s.phase == 0 or s.kind != "hook" or s.hooks == s.order
  val NextIdentity = s.phase == 0 or s.kind != "hook" or s.nextFirst == s.nextSecond
  val MetadataComplete = s.phase == 0 or s.kind != "reflection" or s.built == slotKeys
  val StableIdentity = s.phase != 3 or s.first == s.second
  val RestrictedDemand = s.phase == 0 or s.kind != "restricted" or s.built == Set(3)
  val RejectAll = s.phase != 3
  val safety = HookOrder and NextIdentity and MetadataComplete and StableIdentity and RestrictedDemand
}
module ThunkConstruction { import ThunkConstructionModel(BUG = "none").* }
