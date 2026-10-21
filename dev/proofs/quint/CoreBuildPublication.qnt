// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CoreBuildPublicationModel {
  const BUG: str
  var s: {phase: int, edge: str, attack: str, expected: int, artifact: int,
    record: int, before: bool, after: bool, accepted: bool, a: bool, b: bool,
    parent: int, child: int, unused: int, nativeReturned: bool}
  action init = {
    nondet edge = Set("saved", "direct", "for-export").oneOf()
    nondet attack = Set("none", "both", "artifact", "callback", "failed-build", "preexisting").oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, edge: edge, attack: attack, expected: 1,
      artifact: if (attack == "preexisting") 2 else 1, record: if (attack == "preexisting") 2 else 1, before: false, after: false, accepted: false,
      a: a, b: b, parent: 5432, child: 5433, unused: 0, nativeReturned: true}}
  }
  action issue = all {s.phase == 0,
    s' = s.with("phase", 1)
      .with("artifact", if (s.attack == "preexisting" and BUG == "adopt") 2 else 1)
      .with("record", if (s.attack == "preexisting" and BUG == "adopt") 2 else 1)
      .with("expected", if (s.attack == "preexisting" and BUG == "adopt") 2 else 1)}
  action change = all {s.phase == 1,
    s' = s.with("phase", 2)
      .with("artifact", if (s.attack == "both" or s.attack == "artifact") 2 else s.artifact)
      .with("record", if (s.attack == "both") 2 else s.record)}
  val current = s.attack != "failed-build" and s.artifact == s.expected and s.record == s.expected
  action enter = all {s.phase == 2,
    s' = s.with("phase", 3).with("before",
      current or BUG == "trustDisk" or (BUG == "saved" and s.edge == "saved"))}
  action callback = all {s.phase == 3,
    s' = s.with("phase", 4)
      .with("artifact", if (s.attack == "callback") 2 else s.artifact)}
  action finish = all {s.phase == 4,
    s' = s.with("phase", 5)
      .with("after", current or BUG == "skipReturn" or BUG == "trustDisk" or
          (BUG == "saved" and s.edge == "saved"))
      .with("accepted", s.before and (current or BUG == "skipReturn" or BUG == "trustDisk" or
          (BUG == "saved" and s.edge == "saved")) and s.a and (s.b or BUG == "dropB"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else 0)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {issue, change, enter, callback, finish, terminal}
  val Issued = not(s.accepted) or current
  val Compiled = not(s.accepted) or s.expected == 1
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ParentCache = s.parent == 5432
  val LazyBranch = s.unused == 0
  // An ordinary native cache return is NOT Core publication authority.
  val RejectAll = not(s.accepted)
  val safety = Issued and Compiled and BothRequirements and ParentCache and LazyBranch
}
module CoreBuildPublication { import CoreBuildPublicationModel(BUG = "none").* }
