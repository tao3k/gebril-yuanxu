// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module IssuedRootForwardingModel {
  const BUG: str
  var s: {phase: int, roots: Set[int], forwarded: Set[int], current: bool,
    a: bool, b: bool, accepted: bool, parent: int, child: int, unused: int}
  action init = {
    nondet a = Set(true, false).oneOf()
    nondet b = Set(true, false).oneOf()
    all {s' = {phase: 0, roots: Set(1, 2, 3), forwarded: Set(), current: true,
      a: a, b: b, accepted: false, parent: 5432, child: 5433, unused: 0}}
  }
  action forward = all {s.phase == 0, s' = s.with("phase", 1)
    .with("forwarded", if (BUG == "omit") Set(1, 3) else
      if (BUG == "forge") Set(1, 2, 3, 99) else s.roots)
    .with("unused", if (BUG == "eager") 1 else 0)}
  action edit = {
    nondet current = Set(true, false).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2).with("current", current)}
  }
  action admit = all {s.phase == 2, s' = s.with("phase", 3)
    .with("accepted", s.forwarded.subseteq(Set(1, 2, 3)) and
      (s.current or BUG == "source") and s.a and (s.b or BUG == "dropB"))}
  action done = all {s.phase == 3, s' = s}
  action step = any {forward, edit, admit, done}
  val Coverage = s.phase == 0 or s.roots.subseteq(s.forwarded)
  val Authentic = s.forwarded.subseteq(Set(1, 2, 3))
  val Current = not(s.accepted) or s.current
  val Both = not(s.accepted) or (s.a and s.b)
  val Isolation = s.parent == 5432 and s.child == 5433
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = Coverage and Authentic and Current and Both and Isolation and Lazy
}
module IssuedRootForwarding { import IssuedRootForwardingModel(BUG = "none").* }
