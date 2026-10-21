// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module PersistentSelectedHeadModel {
  const BUG: str
  var s: {phase: int, revision: int, fence: int, expected: int, expectedFence: int,
    head: int, accepted: bool, used: int, usedFence: int, parent: int, unused: int,
    source: bool, restarted: bool, persistedFence: int}
  action init = all {s' = {phase: 0, revision: 0, fence: 0, expected: 0,
    expectedFence: 0, head: 5432, accepted: false, used: 0, usedFence: 0,
    parent: 5432, unused: 0, source: true, restarted: false, persistedFence: 0}}
  action prepare = all {s.phase == 0, s' = s.with("phase", 1)}
  action edit = {
    nondet kind = Set("none", "aba", "revision", "fence", "source").oneOf()
    all {s.phase == 1, s' = s.with("phase", 2)
      .with("revision", if (kind == "aba") s.revision + 2 else if (kind == "revision") s.revision + 1 else s.revision)
      .with("fence", if (kind == "aba") s.fence + 2 else if (kind == "fence") s.fence + 1 else s.fence)
      .with("source", kind != "source")}
  }
  action restart = all {s.phase == 2, s' = s.with("phase", 3).with("persistedFence", s.fence)
    .with("restarted", true).with("fence", if (BUG == "reset") 0 else s.fence)}
  action commit = {
    val ok = (s.revision == s.expected or BUG == "revision") and
             (s.fence == s.expectedFence or BUG == "fence")
    all {s.phase == 3, s' = s.with("phase", 4).with("accepted", ok)
      .with("used", s.revision).with("usedFence", s.fence)
      .with("head", if (ok) 5433 else s.head)
      .with("revision", if (ok) s.revision + 1 else s.revision)
      .with("fence", if (ok) s.fence + 1 else s.fence)}
  }
  action done = all {s.phase == 4, s' = s}
  action step = any {prepare, edit, restart, commit, done}
  val Bound = not(s.accepted) or (s.used == s.expected and s.usedFence == s.expectedFence)
  val Effect = not(s.accepted) or (s.head == 5433 and s.fence == s.usedFence + 1)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val LiveSource = not(s.accepted) or s.source
  val RejectAll = not(s.accepted)
  val Recovery = not(s.restarted) or s.fence >= s.persistedFence
  val safety = Bound and Effect and Parent and Lazy and Recovery
}
module PersistentSelectedHead { import PersistentSelectedHeadModel(BUG = "none").* }
