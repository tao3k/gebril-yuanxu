// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CoreApprovedRecoveryModel {
  const BUG: str
  // Policy is obtained from the governed selected Module, not from candidate
  // metadata. Revision 1 is the actual Source observation made at restoration.
  var s: {phase: int, bound: bool, guarded: bool, warmed: bool, installed: bool, coverage: bool, policy: int, source: int,
    artifact: int, record: int, a: bool, b: bool, accepted: bool, parent: int, unused: int}
  action init = {
    nondet source = Set(1, 2).oneOf()
    nondet files = Set(1, 2).oneOf()
    nondet coverage = Set(false, true).oneOf()
    nondet installed = Set(false, true).oneOf()
    all {s' = {phase: 0, bound: false, guarded: false, warmed: false, installed: installed, coverage: coverage, policy: 1, source: source,
      artifact: files, record: files, a: true, b: true, accepted: false, parent: 5432, unused: 0}}
  }
  val approvalCurrent = s.policy == 1
  val sourceCurrent = s.source == 1
  val filesCurrent = s.artifact == 1 and s.record == 1
  action restore = all {s.phase == 0,
    s' = s.with("phase", 1).with("bound", approvalCurrent and sourceCurrent and filesCurrent
      and (s.coverage or BUG == "coverage") and (s.installed or BUG == "install"))
      .with("guarded", true)}
  action warm = all {s.phase == 1, not(s.warmed),
    s' = s.with("warmed", true).with("guarded", BUG != "warm")}
  action callback = {
    nondet policy = Set(1, 2).oneOf()
    nondet source = Set(1, 2).oneOf()
    nondet files = Set(1, 2).oneOf()
    nondet b = Set(true, false).oneOf()
    all {s.phase == 1, s' = s.with("phase", 2).with("policy", policy)
      .with("source", source).with("artifact", files).with("record", files).with("b", b)}
  }
  action publish = all {s.phase == 2,
    s' = s.with("phase", 3).with("accepted", s.bound and
      (not(s.guarded) or approvalCurrent or BUG == "approval") and (sourceCurrent or BUG == "source") and
      (filesCurrent or BUG == "joint") and s.a and (s.b or BUG == "dropB"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else s.unused)}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {restore, warm, callback, publish, terminal}
  val Approval = not(s.accepted) or approvalCurrent
  val Coverage = not(s.bound) or s.coverage
  val Installed = not(s.bound) or s.installed
  val Source = not(s.accepted) or sourceCurrent
  val Files = not(s.accepted) or filesCurrent
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val RejectAll = not(s.accepted)
  val safety = Installed and Coverage and Approval and Source and Files and Both and Parent and Lazy
}
module CoreApprovedRecovery { import CoreApprovedRecoveryModel(BUG = "none").* }
