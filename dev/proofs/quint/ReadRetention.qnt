// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReadRetentionModel {
  const BUG: str
  // 4 is shared and cyclic; 6 is another slot on receiver 2; 7 is its miss.
  pure def deps(n) = if (n == 1) Set(2, 3) else
    if (n == 2) Set(4, 6) else if (n == 3) Set(4, 7) else
    if (n == 4) Set(2) else Set()
  pure def receiver(n) = if (n == 6 or n == 7) 2 else n
  val required = Set(1, 2, 3, 4, 6, 7)
  var s: {phase: int, todo: Set[int], seen: Set[int], owners: Set[int], work: int,
    current: bool, a: bool, b: bool, accepted: bool, parent: int, child: int, unused: int}
  action init = {
    nondet a = Set(true, false).oneOf()
    nondet b = Set(true, false).oneOf()
    all {s' = {phase: 0, todo: Set(1), seen: Set(), owners: Set(), work: 0,
      current: true, a: a, b: b, accepted: false, parent: 5432, child: 5433, unused: 0}}
  }
  action visit = {
    nondet n = s.todo.oneOf()
    val skip = s.seen.contains(n) or (BUG == "receiver" and s.owners.contains(receiver(n)))
    val children = if (BUG == "miss") deps(n).exclude(Set(7)) else deps(n)
    all {s.phase == 0, s.todo.size() > 0,
      s' = if (skip) s.with("todo", s.todo.exclude(Set(n))) else
        s.with("todo", s.todo.exclude(Set(n)).union(children.exclude(s.seen.union(Set(n)))))
          .with("seen", s.seen.union(Set(n))).with("owners", s.owners.union(Set(receiver(n))))
          .with("work", s.work + 1).with("unused", if (BUG == "eager") 1 else 0)}
  }
  action finish = all {s.phase == 0, s.todo.size() == 0, s' = s.with("phase", 1)}
  action callback = {
    nondet current = Set(true, false).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2).with("current", current)}
  }
  action admit = all {s.phase == 2, s' = s.with("phase", 3)
    .with("accepted", (s.current or BUG == "approval") and s.a and (s.b or BUG == "dropB"))}
  action done = all {s.phase == 3, s' = s}
  action step = any {visit, finish, callback, admit, done}
  val Coverage = s.phase == 0 or required.subseteq(s.seen)
  val IdentityWork = s.work == s.seen.size() and s.work <= required.size()
  val Fresh = not(s.accepted) or s.current
  val Both = not(s.accepted) or (s.a and s.b)
  val Isolation = s.parent == 5432 and s.child == 5433
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = Coverage and IdentityWork and Fresh and Both and Isolation and Lazy
}
module ReadRetention { import ReadRetentionModel(BUG = "none").* }
