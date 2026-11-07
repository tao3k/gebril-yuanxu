// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module NixProfileEffectModel {
  const BUG: str
  var s: {phase: int, revision: int, expected: int, used: int, head: int,
    source: bool, a: bool, b: bool, ready: bool, accepted: bool,
    parent: int, unused: int, restarted: bool}
  action init = {
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, revision: 0, expected: 0, used: 0, head: 5432,
      source: true, a: a, b: b, ready: false, accepted: false,
      parent: 5432, unused: 0, restarted: false}}
  }
  // Workflow preparation uses real domain admission; raw nix-env has no a/b API.
  action prepare = all {s.phase == 0,
    s' = s.with("phase", 1).with("expected", s.revision)
      .with("ready", s.a and (s.b or BUG == "dropB"))}
  action interleave = {
    nondet change = Set("none", "head", "source").oneOf()
    all {s.phase == 1, s' = s.with("phase", 2)
      .with("revision", if (change == "head") s.revision + 1 else s.revision)
      .with("head", if (change == "head") 5440 else s.head)
      .with("source", change != "source")}
  }
  // External profile state survives a new client; this transition is a model
  // projection, not a proof of filesystem or daemon crash durability.
  action restart = all {s.phase == 2, s' = s.with("phase", 3).with("restarted", true)}
  action effect = all {s.phase == 3,
    s' = s.with("phase", 4).with("used", s.revision)
      .with("accepted", s.ready).with("head", if (s.ready) 5433 else s.head)
      .with("revision", if (s.ready) s.revision + 1 else s.revision)
      .with("unused", if (BUG == "eager") 1 else 0)}
  action done = all {s.phase == 4, s' = s}
  action step = any {prepare, interleave, restart, effect, done}
  val Both = not(s.accepted) or (s.a and s.b)
  val Parent = s.parent == 5432
  val Lazy = s.unused == 0
  val Snapshot = not(s.accepted) or (s.head == 5433 and s.restarted)
  val StaleRefused = not(s.accepted) or s.used == s.expected
  val LiveSource = not(s.accepted) or s.source
  val RejectAll = not(s.accepted)
  val safety = Both and Parent and Lazy and Snapshot
}
module NixProfileEffect { import NixProfileEffectModel(BUG = "none").* }
