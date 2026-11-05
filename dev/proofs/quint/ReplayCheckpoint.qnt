// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReplayCheckpointModel {
  const BUG: str
  // Original token support. Graph discovery remains SourceClosureWork's owner.
  type State = {phase: int, dirty: bool, initialDirty: bool, mode: int,
    entry: bool, exit: bool, touched: bool, workError: bool, accepted: bool, cause: int}
  var s: State
  action init = {
    nondet dirty = Set(false, true).oneOf()
    nondet mode = Set(0, 1, 2, 3).oneOf()
    s' = {phase: 0, dirty: dirty, initialDirty: dirty, mode: mode,
      entry: false, exit: false, touched: false, workError: false,
      accepted: false, cause: 0}
  }
  action enter = all {
    s.phase == 0,
    val valid = not(s.dirty) or BUG == "skipEntry"
    s' = s.with("phase", if (valid) 1 else 3)
      .with("entry", BUG != "skipEntry").with("cause", if (valid) 0 else 1)
  }
  action checkpoint = all {
    s.phase == 1,
    // 0: fixed pure checkpoint; 1: selected write/restore attempt;
    // 2: original checkpoint failure; 3: external invalidation before return.
    val write = s.mode == 1
    val workFault = s.mode == 2
    val rejects = (write and BUG != "unprotected") or (workFault and BUG != "swallow")
    s' = s.with("phase", if (rejects) 3 else 2)
      .with("touched", write).with("workError", workFault)
      .with("dirty", if (s.mode == 3) true else s.dirty)
      .with("cause", if (rejects) (if (workFault) 2 else 3) else 0)
  }
  action leave = all {
    s.phase == 2,
    val valid = not(s.dirty) or BUG == "skipExit"
    s' = s.with("phase", 3).with("exit", BUG != "skipExit")
      .with("accepted", valid).with("cause", if (valid) 0 else 1)
  }
  action terminal = all {s.phase == 3, s' = s}
  action step = any {enter, checkpoint, leave, terminal}
  val safety = (not(s.accepted) or
    (s.entry and s.exit and not(s.initialDirty) and not(s.dirty) and
     not(s.touched) and not(s.workError))) and
    (s.phase != 3 or not(s.initialDirty) or s.cause == 1)
}
module ReplayCheckpoint {
  import ReplayCheckpointModel(BUG = "none").*
}
