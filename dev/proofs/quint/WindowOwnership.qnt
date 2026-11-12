// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module WindowOwnershipModel {
  const BUG: str
  type State = {phase: int, kernel: bool, window: bool, kind: int,
    changed: bool, accepted: bool}
  var s: State
  action init = {
    nondet kernel = Set(false, true).oneOf()
    nondet window = Set(false, true).oneOf()
    // 0 ordinary library; 1 eligible owner; 2 unselected Interface;
    // 3 disabled declaration, even when Interface is absent.
    nondet kind = Set(0, 1, 2, 3).oneOf()
    nondet changed = Set(false, true).oneOf()
    s' = {phase: 0, kernel: kernel, window: window or kind == 2,
      kind: kind, changed: changed, accepted: false}
  }
  action check = all {
    s.phase == 0,
    val boundary = if (BUG == "disabledAbsent") s.kind == 1 or s.kind == 2
      else s.kind != 0
    val allowed = not(boundary) or s.kind == 1 or BUG == "skipBoundary"
    val kernel = s.kernel or BUG == "escapeKernel"
    val current = not(s.changed) or BUG == "staleBoundary"
    val prefix = not(BUG == "prefix" and s.window and s.kind == 0)
    s' = s.with("phase", 1).with("accepted", kernel and allowed and current and prefix)
  }
  action step = any {check, all {s.phase == 1, s' = s}}
  val safety = s.phase == 0 or (s.accepted ==
    (s.kernel and (s.kind == 0 or s.kind == 1) and not(s.changed)))
}
module WindowOwnership {
  import WindowOwnershipModel(BUG = "none").*
}
