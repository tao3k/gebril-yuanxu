// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Route selection only. CarrierAdmission owns open carrier checks;
// ReadRetention owns source, both requirements, parent isolation and laziness.
module RoleFunctionModel {
  const BUG: str
  type State = {phase: int, revision: int, baseline: int, unknown: bool, origin: bool,
    fast: bool, carrierRequested: bool, valid: bool, checked: int, invoked: int, bad: bool}
  var s: State
  // False models import under a changed initializer/unknown callback, followed
  // by restoration BEFORE use. Current metadata cannot authenticate that origin.
  action init = {
    nondet origin = Set(true, false).oneOf()
    all {s' = {phase: 0, revision: 0, baseline: 0, unknown: false, origin: origin,
      fast: false, carrierRequested: false, valid: true, checked: 0, invoked: 0, bad: false}
    }
  }
  action edit = all {s.phase == 0,
    s' = s.with("revision", 1).with("phase", 1)}
  action restore = all {s.phase == 1,
    s' = s.with("revision", 2).with("phase", 0)}
  action observe = all {s.phase == 0,
    s' = s.with("unknown", true).with("phase", 2)}
  action ordinary = all {s.phase == 0, s' = s.with("phase", 2)}
  action fromEdit = all {s.phase == 1, s' = s.with("phase", 2)}
  action route = all {s.phase == 2,
    val eligible = (s.revision == s.baseline or BUG == "revision") and
      (not(s.unknown) or BUG == "observer") and (s.origin or BUG == "origin")
    // Actual Generic execution requests carrier support; Function execution
    // has no such demand. CarrierAdmission retains its own before/after laws.
    s' = s.with("fast", eligible).with("carrierRequested", not(eligible) or BUG == "eagerCarrier")
      .with("phase", 3)}
  action validate = {
    nondet valid = Set(false, true).oneOf()
    all {s.phase == 3, s' = s.with("valid", valid).with("phase", 4)
      .with("checked", s.checked + (if (BUG == "memo" and s.invoked > 0) 0 else 1))}
  }
  action invoke = all {s.phase == 4,
    val accepted = s.valid or (BUG == "memo" and s.invoked > 0)
    val unsafe = s.fast and (s.revision != s.baseline or s.unknown or not(s.origin))
    s' = s.with("phase", 5).with("invoked", s.invoked + (if (accepted) 1 else 0))
      .with("bad", s.bad or unsafe or (accepted and not(s.valid)))}
  action nextDatum = all {s.phase == 5, s.invoked == 1, s.checked == 1,
    s' = s.with("phase", 0).with("fast", false).with("carrierRequested", false)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {edit, restore, observe, ordinary, fromEdit, route,
    validate, invoke, nextDatum, terminal}
  val ClosedRoute = not(s.fast) or (s.revision == s.baseline and not(s.unknown) and s.origin)
  val FreshChecks = s.phase < 5 or s.checked >= s.invoked
  val ValidExecution = not(s.bad)
  val NoUnusedCarrier = not(s.fast) or not(s.carrierRequested)
  val RejectAll = s.invoked == 0
  val safety = ClosedRoute and FreshChecks and ValidExecution and NoUnusedCarrier
}
module RoleFunction { import RoleFunctionModel(BUG = "none").* }
