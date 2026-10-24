// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SourceClosureWorkModel {
  const BUG: str
  // Shared diamond, a topology cycle, another root, and a cold unrelated node.
  // These are source-support identities, not an accepted cyclic module import.
  pure val nodes = Set(0, 1, 2, 3, 4, 5)
  pure def deps(n: int): List[int] =
    if (n == 0) List(1, 2) else if (n == 1 or n == 2) List(3)
    else if (n == 3) List(1) else if (n == 4) List(2) else List()
  // Independent saturation oracle; it does not use the implementation worklist.
  pure def reachable(roots: List[int]): Set[int] =
    nodes.fold(roots.foldl(Set(), (out, n) => out.union(Set(n))), (region, _) =>
      region.union(region.fold(Set(), (out, n) =>
        deps(n).foldl(out, (acc, child) => acc.union(Set(child))))))
  pure def edgeCount(region: Set[int]): int =
    region.fold(0, (count, n) => count + deps(n).length())
  type State = {phase: int, roots: List[int], pending: List[int], seen: Set[int],
    visits: int -> int, pops: int, edges: int, versions: int -> int,
    before: Set[int], after: Set[int], beforeReads: int -> int,
    afterReads: int -> int, valid: bool, accepted: bool, held: bool}
  var s: State
  action init = {
    nondet roots = Set(List(0), List(4), List(0, 4)).oneOf()
    s' = {phase: 0, roots: roots,
      pending: if (BUG == "eager") roots.append(5) else roots,
      seen: Set(), visits: nodes.mapBy(_ => 0), pops: 0, edges: 0,
      versions: nodes.mapBy(_ => 0), before: Set(), after: Set(),
      beforeReads: nodes.mapBy(_ => 0), afterReads: nodes.mapBy(_ => 0),
      valid: true, accepted: false, held: false}
  }
  action discover = all {
    s.phase == 0, s.pending.length() > 0, s.pops < 16,
    val n = s.pending.nth(0)
    val rest = s.pending.slice(1, s.pending.length())
    val expand = BUG == "repeat" or not(s.seen.contains(n))
    val children = if (BUG == "drop")
      deps(n).foldl(List(), (out, child) => if (child == 3) out else out.append(child))
      else deps(n)
    s' = s.with("pending", if (expand) children.concat(rest) else rest)
      .with("pops", s.pops + 1)
      .with("seen", s.seen.union(Set(n)))
      .with("visits", if (expand) s.visits.set(n, s.visits.get(n) + 1) else s.visits)
      .with("edges", s.edges + (if (expand) children.length() else 0))
  }
  action beginGuard = all {
    s.phase == 0, s.pending.length() == 0,
    s' = s.with("phase", 1).with("held", true)
  }
  action guardBefore = {
    nondet n = (if (BUG == "wideGuard") nodes else s.seen).exclude(s.before).oneOf()
    all { s.phase == 1,
      s' = s.with("before", s.before.union(Set(n)))
        .with("beforeReads", s.beforeReads.set(n, s.beforeReads.get(n) + 1)) }
  }
  // An opaque callback is an epoch boundary. Versions include native name
  // resolution as well as bytes; topology is immutable within this model.
  action effect = {
    nondet changed = nodes.union(Set(-1)).oneOf()
    all { s.phase == 1, s.before == s.seen,
      s' = s.with("phase", 2)
        .with("versions", if (changed == -1) s.versions else s.versions.set(changed, 1))
        .with("after", if (BUG == "reuse") s.seen else Set()) }
  }
  action guardAfter = {
    nondet n = s.seen.exclude(s.after).oneOf()
    all { s.phase == 2,
      s' = s.with("after", s.after.union(Set(n)))
        .with("afterReads", s.afterReads.set(n, s.afterReads.get(n) + 1))
        .with("valid", s.valid and s.versions.get(n) == 0) }
  }
  action rescan = {
    nondet n = s.before.oneOf()
    all { BUG == "rescan", s.phase == 1,
      s' = s.with("beforeReads", s.beforeReads.set(n, s.beforeReads.get(n) + 1)) }
  }
  action finish = all {
    s.phase == 2, s.after == s.seen,
    s' = s.with("phase", 3).with("held", BUG == "leak")
      .with("accepted", s.valid)
  }
  action terminal = all { s.phase == 3, s' = s }
  action step = any { discover, beginGuard, guardBefore, effect, guardAfter, rescan, finish, terminal }
  val DemandOnly = s.seen.subseteq(reachable(s.roots))
  val UniqueExpansion = nodes.forall(n => s.visits.get(n) <= 1)
  val Complete = s.phase == 0 or s.seen == reachable(s.roots)
  val WorkBound = s.edges == edgeCount(s.seen) and
    s.pops + s.pending.length() == s.roots.length() + s.edges and
    s.pops <= s.roots.length() + edgeCount(reachable(s.roots))
  val PureEpochOnce = nodes.forall(n => s.beforeReads.get(n) <= 1 and s.afterReads.get(n) <= 1)
  val GuardScope = s.before.subseteq(s.seen) and s.after.subseteq(s.seen)
  val Current = not(s.accepted) or s.seen.forall(n => s.versions.get(n) == 0)
  val Cleanup = s.phase != 3 or not(s.held)
  val RejectAll = not(s.accepted)
  val safety = DemandOnly and UniqueExpansion and Complete and WorkBound and PureEpochOnce and GuardScope and Current and Cleanup
}
module SourceClosureWork {
  import SourceClosureWorkModel(BUG = "none").*
}
