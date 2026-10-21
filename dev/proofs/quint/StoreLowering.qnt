// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Isolated compilation domain, not universal SDK/FFI interception.
module StoreLoweringModel {
  const BUG: str
  type State = {phase: int, route: str, a: bool, b: bool, owners: Set[int],
    protected: bool, denied: bool, writes: int, during: int, spec: int,
    parent: int, hot: int, cold: int, unused: int, accepted: bool, planOwner: int}
  var s: State
  action init = {
    nondet route = Set("generated", "reflective", "inline", "unlowered",
      "precompiled-generated", "precompiled-reflective", "precompiled-inline").oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, route: route, a: a, b: b, owners: Set(),
      protected: false, denied: false, writes: 0, during: 0, spec: 5432,
      parent: 5432, hot: 5432, cold: 0, unused: 0, accepted: false, planOwner: 2}}
  }
  action allocate = all {s.phase == 0,
    s' = s.with("phase", 1).with("owners",
      if (BUG == "missConstructor") Set(1,2,3) else
        Set(1,4,5,6).union(Set((1,2),(1,3)).map(edge => edge._2)))}
  action protectReads = all {s.phase == 1,
    s' = s.with("phase", 2).with("protected", BUG != "missCarrier")}
  val precompiled = Set("precompiled-generated", "precompiled-reflective", "precompiled-inline").contains(s.route)
  val mediated = s.route != "unlowered" and not(BUG == "missInline" and s.route == "inline")
    and not(BUG == "missCallback" and precompiled)
  val blocked = mediated and s.protected
  action replace = all {s.phase == 2,
    s' = s.with("phase", 3).with("denied", blocked)
      .with("writes", if (blocked) 0 else 1)
      .with("spec", if (blocked) 5432 else 5440)
      .with("unused", if (BUG == "eager") 1 else 0)}
  action bodyRestore = all {s.phase == 3,
    s' = s.with("phase", 4).with("during", if (s.denied) 0 else 1)
      .with("cold", if (s.denied) 0 else s.spec).with("spec", 5432)
      .with("writes", if (s.denied) 0 else 2)}
  action finish = all {s.phase == 4,
    s' = s.with("phase", 5).with("cold", if (s.cold == 0) s.spec else s.cold)
      .with("accepted", s.a and (s.b or BUG == "dropB"))
      .with("planOwner", if (BUG == "parent") 1 else 2)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {allocate, protectReads, replace, bodyRestore, finish, terminal}
  val OwnerCoverage = s.phase == 0 or Set(1,2,3,4,5,6).subseteq(s.owners)
  val DeclaredPreWrite = s.route == "unlowered" or s.writes == 0
  val NoPoison = s.phase < 5 or s.cold == 5432
  val DeclaredNoPoison = s.route == "unlowered" or NoPoison
  val NoColdDuring = s.route == "unlowered" or s.during == 0
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val ParentCache = s.parent == 5432 and s.hot == 5432
  val LazyBranch = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = OwnerCoverage and DeclaredPreWrite and DeclaredNoPoison and NoColdDuring
    and BothRequirements and ChildPlan and ParentCache and LazyBranch
}
module StoreLowering { import StoreLoweringModel(BUG = "none").* }
