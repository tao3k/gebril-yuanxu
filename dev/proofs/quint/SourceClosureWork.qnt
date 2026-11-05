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
  // An opaque callback is an epoch boundary. Versions include runtime name
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

// Refinement of the existing publication table's native POO topology slot.
// Count identifies immutable append-only membership, never a fresh verdict.
module SessionMetadataIndexModel {
  const BUG: str
  pure val owners = Set(0, 1)
  pure val sources = Set(0, 1, 2, 3)
  type State = {members: Set[int], roots: int -> Set[int],
    indexedCount: int, indexedRoots: Set[int], dirty: Set[int],
    coverage: bool, current: bool, approved: bool, steps: int}
  var s: State
  pure def support(state: State): Set[int] =
    state.members.fold(Set(), (out, owner) => out.union(state.roots.get(owner)))
  action init = s' = {members: Set(), roots: owners.mapBy(owner => Set(owner, 2)),
    indexedCount: -1, indexedRoots: Set(), dirty: Set(),
    coverage: true, current: true, approved: false, steps: 0}
  action insert = {
    nondet owner = owners.oneOf()
    all {s.steps < 5, not(s.members.contains(owner)),
      s' = s.with("members", s.members.union(Set(owner))).with("steps", s.steps + 1)}
  }
  // Illegal same-cardinality replacement demonstrates the necessary premise.
  action replace = {
    nondet owner = owners.oneOf()
    all {BUG == "replace", s.steps < 5, s.members.contains(owner),
      s' = s.with("roots", s.roots.set(owner, Set(3))).with("steps", s.steps + 1)}
  }
  action change = {
    nondet source = sources.oneOf()
    all {s.steps < 5,
      s' = s.with("dirty", s.dirty.union(Set(source))).with("steps", s.steps + 1)}
  }
  action demand = {
    val complete = support(s)
    val rebuilt = if (BUG == "drop") complete.exclude(Set(2)) else complete
    val indexed = if (s.indexedCount != s.members.size()) rebuilt else s.indexedRoots
    val fresh = indexed.intersect(s.dirty) == Set()
    val accepts = fresh or (BUG == "approval" and s.approved)
    all {s.steps < 5,
      s' = s.with("indexedCount", s.members.size()).with("indexedRoots", indexed)
        .with("coverage", s.coverage and indexed == complete)
        .with("current", s.current and (not(accepts) or complete.intersect(s.dirty) == Set()))
        .with("approved", accepts).with("steps", s.steps + 1)}
  }
  action terminal = all {s.steps >= 5, s' = s}
  action step = any {insert, replace, change, demand, terminal}
  val Coverage = s.coverage
  val Current = s.current
  val safety = Coverage and Current
}

// Call-local default authoring support. Token IDs are original issued records;
// the full native event trace, not only roots, is forwarded into the parent.
module AuthoringSupportForwardModel {
  const BUG: str
  pure val events = List(0, 1, 2)
  pure val prior = List(2)
  var s: {phase: int, known: bool, plain: bool, authentic: bool, payload: bool,
          changed: bool, fast: bool, forwarded: List[int], captures: int}
  action init = {
    nondet known = Set(false, true).oneOf()
    nondet plain = Set(false, true).oneOf()
    nondet authentic = Set(false, true).oneOf()
    nondet payload = Set(false, true).oneOf()
    s' = {phase: 0, known: known, plain: plain, authentic: authentic,
          payload: payload, changed: false, fast: false, forwarded: prior, captures: 0}
  }
  action capture = all {
    s.phase == 0,
    s' = s.with("phase", 1).with("captures", 1)
  }
  action pureContinuation = all {
    s.phase == 1,
    s' = s.with("phase", 2).with("changed", BUG == "reuse")
  }
  action forward = all {
    s.phase == 2,
    val fast = s.authentic and s.payload and
      (BUG == "observer" or (s.known and s.plain))
    val trace = if (BUG == "drop") List(0, 1)
      else if (BUG == "duplicate") events.concat(events) else events
    s' = s.with("phase", 3).with("fast", fast)
      .with("forwarded", if (fast) prior.concat(trace) else prior)
  }
  action terminal = all { s.phase == 3, s' = s }
  action step = any { capture, pureContinuation, forward, terminal }
  val Trace = not(s.fast) or s.forwarded == prior.concat(events)
  val Eligibility = not(s.fast) or (s.known and s.plain and s.authentic and s.payload)
  val Current = not(s.fast) or not(s.changed)
  val SingleCapture = s.phase == 0 or s.captures == 1
  val safety = Trace and Eligibility and Current and SingleCapture
}

// Bare lexical role alias lowering. Values stand for exact object identities;
// a single native receiver/name read must retain its original lazy demand.
module DirectRoleAliasModel {
  const BUG: str
  type State = {done: bool, receiver: int, name: int, bare: bool, shadowed: bool,
    fast: bool, value: int, reads: List[int]}
  var s: State
  action init = {
    nondet receiver = Set(0, 1).oneOf()
    nondet name = Set(0, 1, 2).oneOf()
    nondet bare = Set(true, false).oneOf()
    nondet shadowed = Set(true, false).oneOf()
    s' = {done: false, receiver: receiver, name: name, bare: bare, shadowed: shadowed,
      fast: false, value: -1, reads: List()}
  }
  pure def eligible(n: int, bare: bool, hidden: bool): bool =
    bare and n < 2 and not(hidden)
  action lower = all {
    not(s.done),
    val fast = eligible(s.name, s.bare, s.shadowed) or
      (BUG == "shadow" and s.bare and s.name < 2)
    val receiver = if (BUG == "receiver") 0 else s.receiver
    val selected = if (BUG == "alias" and fast) 1 - s.name else s.name
    s' = s.with("done", true).with("fast", fast)
      .with("value", if (fast) receiver * 100 + selected + 10 else
        (if (eligible(s.name, s.bare, s.shadowed)) s.receiver * 100 + s.name + 10 else s.name + 20))
      .with("reads", if (fast) List(receiver, selected) else
        (if (eligible(s.name, s.bare, s.shadowed)) List(s.receiver, s.name) else List()))
  }
  action terminal = all { s.done, s' = s }
  action step = any { lower, terminal }
  val Eligibility = not(s.fast) or eligible(s.name, s.bare, s.shadowed)
  val Identity = not(s.done) or s.value ==
    (if (eligible(s.name, s.bare, s.shadowed)) s.receiver * 100 + s.name + 10 else s.name + 20)
  val NativeDemand = not(s.fast) or s.reads == List(s.receiver, s.name)
  val safety = Eligibility and Identity and NativeDemand
}
