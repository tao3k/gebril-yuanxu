// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RootCollectionModel {
  const BUG: str
  val input = [1, 2, 1, 3, 2, 4]
  val originalEdges = [(1, 3), (2, 3), (1, 3)]
  pure def has(xs, n) = xs.foldl(false, (found, x) => found or x == n)
  pure def firsts(xs) = xs.foldl([], (kept, n) =>
    if (has(kept, n)) kept else kept.append(n))
  pure def events(xs) = xs.foldl([], (log, n) => log.append(n * 10 + 1).append(n * 10 + 2))
  pure def firstBad(xs, bad) = xs.foldl(0, (found, n) =>
    if (found == 0 and bad.contains(n)) n else found)
  pure def receiver(n) = if (n == 2 or n == 4) 1 else n
  var s: {pos: int, roots: List[int], calls: List[int], edges: List[(int, int)], bad: Set[int]}
  action init = {
    nondet bad = Set(Set(), Set(1), Set(2), Set(3), Set(4), Set(1, 2), Set(2, 3), Set(3, 4)).oneOf()
    all {s' = {pos: 0, roots: [], calls: [], edges: originalEdges, bad: bad}}
  }
  action deliver = {
    val n = input.nth(s.pos)
    val duplicate = if (BUG == "receiver") s.roots.foldl(false, (found, x) => found or receiver(x) == receiver(n))
      else has(s.roots, n)
    val retained = if (duplicate) s.roots else s.roots.append(if (BUG == "copy") n + 10 else n)
    val roots = if (BUG == "reverse") retained.foldl([], (acc, x) => [x].concat(acc)) else retained
    val calls = if (BUG == "suppress" and duplicate) s.calls else
      if (BUG == "observerOrder") s.calls.append(n * 10 + 2).append(n * 10 + 1)
      else s.calls.append(n * 10 + 1).append(n * 10 + 2)
    all {s.pos < input.length(), s' = s.with("pos", s.pos + 1).with("roots", roots)
      .with("calls", calls).with("edges", if (BUG == "edges") [(1, 3), (2, 3)] else s.edges)}
  }
  action done = all {s.pos == input.length(), s' = s}
  action step = any {deliver, done}
  val IdentityOrder = s.roots == firsts(input.slice(0, s.pos))
  val ObserverOrder = s.calls == events(input.slice(0, s.pos))
  val Edges = s.edges == originalEdges
  val FirstDiagnostic = firstBad(s.roots, s.bad) == firstBad(input.slice(0, s.pos), s.bad)
  val NoWork = s.pos == 0
  val safety = IdentityOrder and ObserverOrder and Edges and FirstDiagnostic
}
module RootCollection { import RootCollectionModel(BUG = "none").* }
