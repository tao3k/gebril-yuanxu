// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SourceLoaderModel {
  const BUG: str
  var s: {phase: int, edge: str, changed: bool, checked: bool, returned: bool,
    a: bool, b: bool, published: bool, parent: int, unused: int}
  action init = {
    nondet edge = Set("saved", "direct", "reload", "retry").oneOf()
    nondet changed = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, edge: edge, changed: changed, checked: false,
      returned: false, a: a, b: b, published: false, parent: 5432, unused: 0}}
  }
  action enter = all {s.phase == 0,
    s' = s.with("phase", 1).with("checked",
      not((BUG == "oldEdge" and s.edge == "saved") or
          (BUG == "reload" and s.edge == "reload") or
          (BUG == "retry" and s.edge == "retry")))}
  action cached = all {s.phase == 1,
    s' = s.with("phase", 2).with("returned", not(s.checked and s.changed))}
  action publish = all {s.phase == 2,
    s' = s.with("phase", 3)
      .with("published", s.returned and s.a and (s.b or BUG == "dropB"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else s.unused)}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {enter, cached, publish, terminal}
  val EntryCoverage = s.phase < 2 or not(s.returned) or (s.checked and not(s.changed))
  val BothRequirements = not(s.published) or (s.a and s.b)
  val ParentCache = s.parent == 5432
  val LazyBranch = s.unused == 0
  val RejectAll = not(s.returned)
  val safety = EntryCoverage and BothRequirements and ParentCache and LazyBranch
}
module SourceLoader { import SourceLoaderModel(BUG = "none").* }
