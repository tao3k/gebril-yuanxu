// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CoreStoreRecoveryModel {
  const BUG: str
  var s: { phase: int, selected: int, candidate: int, registered: bool,
    nar: bool, regular: bool, source: bool, artifact: int, record: int, bound: bool,
    accepted: bool, a: bool, b: bool, parent: int, unused: int }
  action init = {
    nondet candidate = Set(1, 2).oneOf()
    nondet registered = Set(false, true).oneOf()
    nondet nar = Set(false, true).oneOf()
    nondet regular = Set(false, true).oneOf()
    nondet source = Set(false, true).oneOf()
    nondet artifact = Set(1, 2).oneOf()
    nondet record = Set(1, 2).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, selected: 1, candidate: candidate,
      registered: registered, nar: nar, regular: regular, source: source, artifact: artifact,
      record: record, bound: false, accepted: false, a: a, b: b, parent: 5432, unused: 0}}
  }
  val root = s.candidate == s.selected and s.registered and s.nar and s.regular
  val current = s.source and s.artifact == s.candidate and s.record == s.candidate
  action restore = all {s.phase == 0,
    s' = s.with("phase", 1).with("bound", current and
      (s.candidate == s.selected or BUG == "pin") and
      (s.registered or BUG == "registry") and (s.nar or BUG == "nar") and
      (s.regular or BUG == "asset"))}
  action callback = {
    nondet source = Set(false, true).oneOf()
    nondet artifact = Set(1, 2).oneOf()
    nondet record = Set(1, 2).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2).with("source", source)
      .with("artifact", artifact).with("record", record)}
  }
  action publish = all {s.phase == 2,
    s' = s.with("phase", 3).with("accepted", s.bound and
      (current or BUG == "tail") and s.a and (s.b or BUG == "dropB"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else s.unused)}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {restore, callback, publish, terminal}
  val Origin = not(s.bound) or root
  val Final = not(s.accepted) or current
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = Origin and Final and Both and Parent and Lazy
}
module CoreStoreRecovery { import CoreStoreRecoveryModel(BUG = "none").* }
