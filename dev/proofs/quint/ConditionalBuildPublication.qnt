// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ConditionalBuildPublicationModel {
  const BUG: str
  var s: {phase: int, version: int, expected: int, ready: bool,
    a: bool, b: bool, accepted: bool, installed: int,
    parent: int, unused: int, external: int}
  action init = {
    nondet a = Set(true, false).oneOf()
    nondet b = Set(true, false).oneOf()
    all { s' = {phase: 0, version: 0, expected: 0, ready: false,
      a: a, b: b, accepted: false, installed: 5432,
      parent: 5432, unused: 0, external: 0} }
  }
  action prepare = all {s.phase == 0,
    s' = s.with("phase", 1).with("expected", s.version)
      .with("ready", s.a and (s.b or BUG == "dropB"))}
  action change = {
    nondet mode = Set("none", "aba", "external").oneOf()
    all { s.phase == 1,
      s' = s.with("phase", 2)
        .with("version", if (mode == "aba") s.version + 2 else s.version)
        .with("external", if (mode == "external") 1 else 0) }
  }
  action commit = all {s.phase == 2,
    s' = s.with("phase", 3).with("accepted",
      s.ready and
      (s.version == s.expected or BUG == "split"))
      .with("installed", if (s.ready and
        (s.version == s.expected or BUG == "split")) 5433 else s.installed)
      .with("unused", if (BUG == "eager") 1 else 0) }
  action done = all {s.phase == 3, s' = s}
  action step = any {prepare, change, commit, done}
  val Revision = not(s.accepted) or s.version == s.expected
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val ExactPlan = not(s.accepted) or s.installed == 5433
  val External = not(s.accepted) or s.external == 0
  val RejectAll = not(s.accepted)
  val safety = Revision and Both and Parent and Lazy and ExactPlan
}
module ConditionalBuildPublication { import ConditionalBuildPublicationModel(BUG = "none").* }
