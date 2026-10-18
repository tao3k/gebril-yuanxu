// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Actual shared-payload restoration counterexample; no new write gateway.
module MetadataAllocationModel {
  const BUG: str
  type State = {phase: int, path: str, a: bool, b: bool,
    owners: Set[int], selected: Set[int], denied: bool, writes: int,
    spec: int, parentCache: int, hotCache: int, coldCache: int,
    revision: int, accepted: bool, planOwner: int, unused: int}
  var s: State
  action init = {
    nondet path = Set("supported", "generated", "reflective").oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, path: path, a: a, b: b, owners: Set(1),
      selected: Set(2), denied: false, writes: 0, spec: 5432,
      parentCache: 5432, hotCache: 5432, coldCache: 0,
      revision: 0, accepted: false, planOwner: 2, unused: 0}}
  }
  // Allocation/derivation registers all consumers of one shared specification.
  // This reverse ownership ledger is a DESIGN; native tests observe the aliases.
  action inherit = all {s.phase == 0,
    s' = s.with("phase", 1).with("owners",
      if (BUG == "lastOwner") Set(3) else s.owners.union(Set(2,3)))}
  val blocked = s.path == "supported" and s.owners.intersect(s.selected).size() > 0
  action replace = all {s.phase == 1,
    s' = s.with("phase", 2).with("denied", blocked)
      .with("writes", if (blocked) 0 else 1)
      .with("spec", if (blocked) s.spec else 5440)
      .with("unused", if (BUG == "eager") 1 else 0)}
  // Cold is deliberately read in the counterexample; unused remains unselected.
  action forceCold = all {s.phase == 2,
    s' = s.with("phase", 3).with("coldCache", s.spec)}
  action restore = all {s.phase == 3,
    s' = s.with("phase", 4).with("spec", 5432)
      .with("writes", if (s.denied) s.writes else s.writes + 1)}
  action finish = all {s.phase == 4,
    s' = s.with("phase", 5).with("accepted", s.a and (s.b or BUG == "dropB"))
      .with("planOwner", if (BUG == "parent") 1 else 2)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {inherit, replace, forceCold, restore, finish, terminal}
  val SupportedPreWrite = s.path != "supported" or s.writes == 0
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val ParentCache = s.parentCache == 5432 and s.hotCache == 5432
  val LazyBranch = s.unused == 0
  // False for actual raw setters, even with setters omitted from a facade.
  val RestoredImpliesCoherent = s.phase < 4 or s.coldCache == s.spec
  val HiddenExportsStopReflection = s.path != "reflective" or s.writes == 0
  val RejectAll = not(s.accepted)
  val safety = SupportedPreWrite and BothRequirements and ChildPlan and ParentCache and LazyBranch
}
module MetadataAllocation { import MetadataAllocationModel(BUG = "none").* }
