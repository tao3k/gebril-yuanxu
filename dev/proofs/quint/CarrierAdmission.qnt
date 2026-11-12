// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Candidate construction, checked handoff, open callback and checked return.
module CarrierAdmissionModel {
  const BUG: str
  type State = {phase: int, hook: bool, valid: bool, checks: int,
    hookUnchecked: bool, executedInvalid: bool, executed: bool}
  var s: State
  action init = {
    nondet hook = Set(false, true).oneOf()
    nondet valid = Set(false, true).oneOf()
    s' = {phase: 0, hook: hook, valid: valid, checks: 0,
      hookUnchecked: false, executedInvalid: false, executed: false}
  }
  // Protocol lookup can have effects BEFORE the single default admission.
  action lookup = {
    nondet changed = Set(false, true).oneOf()
    all {s.phase == 0, s' = s.with("phase", 1).with("valid", s.valid and not(changed))}
  }
  action admit = all {s.phase == 1,
    val allowed = s.valid or BUG == "skipBefore"
    s' = s.with("phase", if (allowed) 2 else 5)
      .with("checks", if (BUG == "skipBefore") 0 else 1)}
  action closed = all {s.phase == 2, not(s.hook),
    s' = s.with("phase", 5).with("executed", true)
      .with("executedInvalid", not(s.valid))}
  action callback = {
    nondet changed = Set(false, true).oneOf()
    all {s.phase == 2, s.hook,
      s' = s.with("phase", 3).with("hookUnchecked", s.checks != 1 or not(s.valid))
        .with("valid", s.valid and not(changed))}
  }
  action returned = all {s.phase == 3,
    val allowed = s.valid or BUG == "skipAfter"
    s' = s.with("phase", if (allowed) 4 else 5)
      .with("checks", s.checks + (if (BUG == "skipAfter") 0 else 1))}
  action execute = all {s.phase == 4,
    s' = s.with("phase", 5).with("executed", true)
      .with("executedInvalid", not(s.valid))}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {lookup, admit, closed, callback, returned, execute, terminal}
  val CheckedHandoff = not(s.hookUnchecked)
  val ValidExecution = not(s.executedInvalid)
  val ExactChecks = not(s.executed) or s.checks == (if (s.hook) 2 else 1)
  val RejectAll = not(s.executed)
  val safety = CheckedHandoff and ValidExecution and ExactChecks
}
module CarrierAdmission {
  import CarrierAdmissionModel(BUG = "none").*
}
