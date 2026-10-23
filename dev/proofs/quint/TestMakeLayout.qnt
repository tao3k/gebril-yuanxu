// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module TestMakeLayoutModel {
  const BUG: str
  // Start at a valid restored warm publication. Native Make's source/dependency
  // timestamps are stable; only target layout can make the expected output miss.
  var s: {phase: int, expectedMatches: bool, roots: int, compiles: int, source: int,
    a: bool, b: bool, accepted: bool, parent: int, unused: int}
  action init = {
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    nondet roots = Set(1, 2).oneOf()
    all {s' = {phase: 0, expectedMatches: BUG != "absolute", roots: roots, compiles: 0,
      source: 1, a: a, b: b, accepted: false, parent: 5432, unused: 0}}
  }
  action make = all {s.phase == 0,
    s' = s.with("phase", 1).with("compiles", if (s.expectedMatches) 0 else s.roots)}
  action callback = {
    nondet source = Set(1, 2).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2).with("source", source)}
  }
  action finish = all {s.phase == 2,
    // Recompiling into the existing product leaves an unissued generation.
    // Keeping this refusal is essential, but it does not repair wasted work.
    s' = s.with("phase", 3).with("accepted", s.compiles == 0 and s.a and s.b
      and (s.source == 1 or BUG == "skipSource"))}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {make, callback, finish, terminal}
  val NoWork = s.compiles == 0
  val Current = not(s.accepted) or s.source == 1
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = NoWork and Current and Both and Parent and Lazy
}
module TestMakeLayout { import TestMakeLayoutModel(BUG = "none").* }
