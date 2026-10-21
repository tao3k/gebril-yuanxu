// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReaderEffectSupportModel {
  const BUG: str
  // 0/1 are actual native imports; 2 is an earlier publication reachable
  // through ambient state; 3 is an already observed Schema/policy source.
  pure val imports = Set(0, 1)
  pure val prefix = Set(0, 1, 2, 3)
  type State = {phase: int, confined: bool, dirty: Set[int],
    enteredDirty: bool, returnedDirty: bool, accepted: bool, held: bool}
  var s: State
  pure def support(confined: bool): Set[int] =
    if (confined) imports else prefix
  pure def current(dirty: Set[int], checked: Set[int]): bool =
    dirty.intersect(checked) == Set()
  action init = {
    nondet confined = Set(false, true).oneOf()
    nondet changed = prefix.union(Set(-1)).oneOf()
    s' = {phase: 0, confined: confined,
      dirty: if (changed == -1) Set() else Set(changed), enteredDirty: false,
      returnedDirty: false, accepted: false, held: true}
  }
  action enter = all {
    s.phase == 0,
    // Native import discovery does NOT certify confinement of an initializer.
    val checked = if (BUG == "importsOnly") imports else support(s.confined)
    val allowed = current(s.dirty, checked)
    s' = s.with("phase", if (allowed) 1 else 3)
      .with("enteredDirty", allowed and not(current(s.dirty, support(s.confined))))
      .with("held", allowed)
  }
  action initializer = {
    nondet changed = support(s.confined).union(Set(-1)).oneOf()
    all { s.phase == 1,
      s' = s.with("phase", 2).with("dirty",
        if (changed == -1) s.dirty else s.dirty.union(Set(changed))) }
  }
  action returned = all {
    s.phase == 2,
    val checked = if (BUG == "returnImports") imports else support(s.confined)
    val allowed = current(s.dirty, checked)
    s' = s.with("phase", 3)
      .with("returnedDirty", allowed and not(current(s.dirty, support(s.confined))))
      .with("accepted", allowed and current(s.dirty, prefix))
      .with("held", BUG == "cleanup")
  }
  action terminate = all { s.phase < 3,
    s' = s.with("phase", 3).with("held", BUG == "cleanup") }
  action terminal = all { s.phase == 3, s' = s }
  action step = any {enter, initializer, returned, terminate, terminal}
  val EntrySupport = not(s.enteredDirty)
  val ReturnSupport = not(s.returnedDirty)
  val FinalSupport = not(s.accepted) or current(s.dirty, prefix)
  val Cleanup = s.phase != 3 or not(s.held)
  val RejectAll = not(s.accepted)
  val safety = EntrySupport and ReturnSupport and FinalSupport and Cleanup
}
module ReaderEffectSupport {
  import ReaderEffectSupportModel(BUG = "none").*
}
