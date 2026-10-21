// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ContextWalkModel {
  const BUG: str
  pure val nodes = Set(0, 1, 2, 3, 4, 5)
  pure def deps(n: int): List[int] =
    if (n == 0) List(1, 2) else if (n == 1 or n == 2) List(3)
    else if (n == 3) List(1) else if (n == 4) List(2) else List()
  type Frame = {pending: List[int], after: int}
  type State = {frames: List[Frame], seen: Set[int], calls: int -> int,
    order: List[int], cut: int}
  var s: State
  pure def expected(cut: int): List[int] =
    if (cut == 1) List(1, 3, 2, 0, 4) else List(3, 1, 2, 0, 4)
  action init = {
    nondet cut = Set(-1, 1, 3).oneOf()
    s' = {frames: List({pending: if (BUG == "eager") List(0, 4, 0, 5) else List(0, 4, 0), after: -1}),
      seen: Set(), calls: nodes.mapBy(_ => 0), order: List(), cut: cut}
  }
  action advance = all {
    s.frames.length() > 0,
    val frame = s.frames.nth(0)
    val outer = s.frames.slice(1, s.frames.length())
    s' = if (frame.pending.length() == 0)
      s.with("frames", outer).with("order",
        if (frame.after == -1 or BUG == "preorder" or (BUG == "dropAfter" and frame.after == 1))
        s.order else s.order.append(frame.after))
    else {
      val n = frame.pending.nth(0)
      val remaining = List({pending: frame.pending.slice(1, frame.pending.length()), after: frame.after}).concat(outer)
      val seen = if (BUG == "forgetShared" and n == 4) Set() else s.seen
      if (seen.contains(n)) s.with("frames", remaining)
      else {
        val descend = BUG == "ignoreCut" or n != s.cut
        s.with("seen", if (BUG == "lateMark") seen else seen.union(Set(n)))
          .with("calls", s.calls.set(n, s.calls.get(n) + 1))
          .with("frames", if (descend) List({pending: deps(n), after: n}).concat(remaining) else remaining)
          .with("order", if (BUG == "preorder" or not(descend)) s.order.append(n) else s.order)
      }
    }
  }
  action terminal = all { s.frames.length() == 0, s' = s }
  action step = any { advance, terminal }
  val UniqueEntry = nodes.forall(n => s.calls.get(n) <= 1)
  val Prefix = s.order.length() <= expected(s.cut).length() and
    s.order.indices().forall(i => s.order.nth(i) == expected(s.cut).nth(i))
  val Complete = s.frames.length() != 0 or s.order == expected(s.cut)
  val Lazy = not(s.seen.contains(5))
  val RejectAll = s.frames.length() != 0
  val safety = UniqueEntry and Prefix and Complete and Lazy
}
module ContextWalk { import ContextWalkModel(BUG = "none").* }
