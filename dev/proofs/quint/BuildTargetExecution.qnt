// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module BuildTargetExecutionModel {
  const BUG: str
  var s: {phase: int, revision: int, clean: bool, inputs: int, locked: bool,
    issued: bool, effect: bool, safeEffect: bool, accepted: bool}

  action init = {
    nondet clean = Set(true, false).oneOf()
    all { s' = {phase: 0, revision: 1, clean: clean, inputs: 0, locked: false,
      issued: true, effect: false, safeEffect: false, accepted: false} }
  }
  action prepare = all { s.phase == 0,
    s' = s.with("phase", 1).with("inputs", if (s.clean and BUG != "eager") 0 else 1) }
  action before = {
    nondet revision = Set(1, 2).oneOf()
    all { s.phase == 1, s' = s.with("phase", 2).with("revision", revision)
      .with("locked", s.clean and BUG != "unlocked")
      .with("issued", not(s.clean and revision == 1 and BUG != "issued")) }
  }
  action effect = all { s.phase == 2,
    s' = s.with("phase", 3)
      .with("effect", s.revision == 1 or BUG == "stale")
      .with("safeEffect", s.revision == 1 and (not(s.clean) or (s.locked and not(s.issued)))) }
  action after = {
    nondet revision = Set(s.revision, 2).oneOf()
    all { s.phase == 3, s' = s.with("phase", 4).with("revision", revision)
      .with("accepted", s.effect and (revision == 1 or BUG == "no-return"))
      .with("locked", false) }
  }
  action done = all { s.phase == 4, s' = s }
  action step = any { prepare, before, effect, after, done }

  val safety = (not(s.clean) or s.inputs == 0)
    and (not(s.effect) or s.safeEffect)
    and (not(s.accepted) or s.revision == 1)
}
module BuildTargetExecution { import BuildTargetExecutionModel(BUG = "none").* }
module BuildTargetExecution_eager { import BuildTargetExecutionModel(BUG = "eager").* }
module BuildTargetExecution_unlocked { import BuildTargetExecutionModel(BUG = "unlocked").* }
module BuildTargetExecution_issued { import BuildTargetExecutionModel(BUG = "issued").* }
module BuildTargetExecution_stale { import BuildTargetExecutionModel(BUG = "stale").* }
module BuildTargetExecution_noReturn { import BuildTargetExecutionModel(BUG = "no-return").* }
