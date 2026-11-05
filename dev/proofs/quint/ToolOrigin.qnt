// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ToolOriginModel {
  const BUG: str
  type State = {phase: int, source: bool, owned: bool, dirty: bool,
    alias: bool, associated: bool, changed: int, open: bool, removed: bool, returnChanged: bool, accepted: bool}
  var s: State
  action init = {
    nondet source = Set(false, true).oneOf()
    nondet owned = Set(false, true).oneOf()
    nondet dirty = Set(false, true).oneOf()
    // 0 stable; 1 context replacement; 2 module-ID edit; 3 artifact-path edit.
    nondet changed = Set(0, 1, 2, 3).oneOf()
    nondet alias = Set(false, true).oneOf()
    nondet associated = Set(false, true).oneOf()
    nondet open = Set(false, true).oneOf()
    nondet removed = Set(false, true).oneOf()
    nondet returnChanged = Set(false, true).oneOf()
    // Fixed closed checkpoints contain no external effect. An open callback
    // may remove itself without erasing its already captured return boundary.
    s' = {phase: 0, source: source, owned: owned, dirty: dirty,
      alias: alias, associated: associated, changed: changed, open: open, removed: removed,
      returnChanged: open and returnChanged, accepted: false}
  }
  action check = all {
    s.phase == 0,
    val binding = s.changed == 0 or BUG == "skipBinding"
    val returnCheck = if (BUG == "skipReturn") false
      else if (BUG == "liveObserver") s.open and not(s.removed)
      else s.open
    val returned = not(returnCheck) or not(s.returnChanged)
    val aliasOK = not(s.alias) or
      ((s.owned or BUG == "unownedAlias") and (s.associated or BUG == "skipAssociation"))
    val needed = if (BUG == "overCapture") true
      else if (BUG == "skipSource") false
      else s.source or (s.owned and BUG != "skipBuild")
    s' = s.with("phase", 1).with("accepted", binding and returned and aliasOK and (not(needed) or not(s.dirty)))
  }
  action terminal = all {s.phase == 1, s' = s}
  action step = any {check, terminal}
  val safety = s.phase == 0 or
    (s.accepted == (s.changed == 0 and not(s.returnChanged) and (not(s.alias) or (s.owned and s.associated)) and (not(s.source or s.owned) or not(s.dirty))))
}
module ToolOrigin {
  import ToolOriginModel(BUG = "none").*
}
