// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CoreBuildHandoffModel {
  const BUG: str
  var s: { phase: int, selection: int, expected: int, artifact: int,
    record: int, bound: bool, accepted: bool, a: bool, b: bool,
    parent: int, unused: int, sourceCurrent: bool }
  action init = {
    nondet selection = Set(1, 2).oneOf()
    nondet artifact = Set(1, 2).oneOf()
    nondet record = Set(1, 2).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all { s' = {phase: 0, selection: selection, expected: 1,
      artifact: artifact, record: record, bound: false, accepted: false,
      a: a, b: b, parent: 5432, unused: 0, sourceCurrent: true} }
  }
  val current = s.selection == 1 and s.artifact == s.expected and s.record == s.expected
  action bind = all {s.phase == 0,
    s' = s.with("phase", 1)
      .with("expected", if (BUG == "disk") s.artifact else s.expected)
      .with("bound", current or (BUG == "disk" and s.artifact == s.record) or
        (BUG == "selection" and s.artifact == 1 and s.record == 1))}
  action callback = {
    nondet artifact = Set(1, 2).oneOf()
    nondet record = Set(1, 2).oneOf()
    nondet sourceCurrent = Set(false, true).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2)
      .with("artifact", artifact).with("record", record)
      .with("sourceCurrent", sourceCurrent)}
  }
  action publish = all {s.phase == 2,
    s' = s.with("phase", 3)
      .with("accepted", s.bound and (current or BUG == "tail") and s.a and s.b and
        (s.sourceCurrent or BUG == "source"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else s.unused)}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {bind, callback, publish, terminal}
  val Origin = not(s.bound) or (s.selection == 1 and s.expected == 1)
  val Final = not(s.accepted) or (current and s.sourceCurrent)
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = Origin and Final and Both and Parent and Lazy
}
module CoreBuildHandoff { import CoreBuildHandoffModel(BUG = "none").* }
