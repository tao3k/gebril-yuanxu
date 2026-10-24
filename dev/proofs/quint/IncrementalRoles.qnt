// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Code imports and value reads are different relations; no heap-byte claim.
// Node 2 is runtime/JSON data, NOT an edited Scheme config.ss source file.
module IncrementalRolesModel {
  const BUG: str
  val nodes = Set(1, 2, 3, 4, 5, 6)
  val demanded = Set(1, 2, 3, 4, 6)
  val code = Set(1, 4, 6)
  // Finite graph is explicit data: same three value edges, one import edge.
  // Keeping edges as data avoids expanding nested dispatch functions in TLA+.
  val compileEdges = Set((6, 1))
  val valueEdges = Set((3, 2), (3, 6), (6, 1))
  val registeredEdges = if (BUG == "drop-edge") Set() else valueEdges
  pure def expand(seen, edges) = seen.union(
    edges.filter(edge => seen.contains(edge._2)).map(edge => edge._1))
  // Fixture maximum path length is two; no arbitrary graph closure claim.
  pure def impact(changed, compileOnly) = {
    val edges = if (compileOnly) compileEdges else valueEdges
    expand(expand(changed, edges), edges)
  }
  pure def nativeImpact(changed) = expand(expand(changed, registeredEdges), registeredEdges)
  val Registration = valueEdges.subseteq(registeredEdges)
  val trace = List(1, 2, 3, 3, 4, 6)
  var s: {phase: int, dataOnly: bool, changed: Set[int], invalid: Set[int],
    compiled: Set[int], evaluated: Set[int], reused: Set[int],
    source: int, checked: int, a: bool, b: bool, accepted: bool,
    observed: List[int], parent: int, child: int}
  action init = {
    nondet dataOnly = Set(true, false).oneOf()
    nondet a = Set(true, false).oneOf()
    nondet b = Set(true, false).oneOf()
    all {s' = {phase: 0, dataOnly: dataOnly, changed: Set(), invalid: Set(),
      compiled: Set(), evaluated: Set(), reused: demanded, source: 0, checked: 0,
      a: a, b: b, accepted: false, observed: List(), parent: 5432, child: 5432}}
  }
  action edit = {
    val changed = if (s.dataOnly) Set(2) else Set(1)
    val affected = nativeImpact(changed)
    all {s.phase == 0, s' = s.with("phase", 1).with("changed", changed)
      .with("invalid", affected.intersect(demanded)).with("source", 1)}
  }
  action materialize = {
    val compileWork = if (s.dataOnly) Set() else impact(s.changed, true).intersect(code)
    all {s.phase == 1, s' = s.with("phase", 2)
      .with("compiled", if (BUG == "global-compile") code else compileWork)
      .with("evaluated", s.invalid).with("reused", demanded.exclude(s.invalid))
      .with("observed", if (BUG == "observer") List(1, 2, 3, 4, 6) else trace)
      .with("checked", s.source).with("child", 5433)
      .with("parent", if (BUG == "parent") 5433 else s.parent)}
  }
  action effect = {
    nondet changed = Set(true, false).oneOf()
    all {s.phase == 2, s' = s.with("phase", 3).with("source", if (changed) 2 else s.source)}
  }
  action admit = all {s.phase == 3, s' = s.with("phase", 4)
    .with("accepted", s.a and (s.b or BUG == "dropB") and
      (s.source == s.checked or BUG == "cached-admission"))}
  action done = all {s.phase == 4, s' = s}
  action step = any {edit, materialize, effect, admit, done}
  val Invalidation = s.phase == 0 or s.invalid == impact(s.changed, false).intersect(demanded)
  val Compilation = s.phase < 2 or s.compiled ==
    (if (s.dataOnly) Set() else impact(s.changed, true).intersect(code))
  val Partition = s.phase < 2 or
    (s.evaluated.intersect(s.reused) == Set() and s.evaluated.union(s.reused) == demanded)
  val Observer = s.phase < 2 or s.observed == trace
  val Current = not(s.accepted) or s.source == s.checked
  val Both = not(s.accepted) or (s.a and s.b)
  val Isolation = s.parent == 5432
  val Lazy = not(s.evaluated.contains(5)) and not(s.compiled.contains(5))
  val NoAcceptance = not(s.accepted)
  val safety = Registration and Invalidation and Compilation and Partition and Observer and Current and Both and Isolation and Lazy
}
module IncrementalRoles { import IncrementalRolesModel(BUG = "none").* }
