// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SnapshotEntryModel {
  const BUG: str
  type View = {checker: int, revision: int, instance: int, prepared: bool, value: int,
    protocol: int, ancestor: int, observer: int}
  type State = {phase: int, old: View, live: View, mode: int, source: int,
    priorCallback: bool, guarded: bool, eligible: bool, called: bool,
    owner: int, requiredA: bool, requiredB: bool, stalePrefix: bool,
    fault: int, accepted: bool}
  var s: State
  pure def matches(a: View, b: View): bool =
    if (BUG == "revision") a.revision == b.revision
    else (BUG == "checker" or a.checker == b.checker) and a.revision == b.revision and
      a.instance == b.instance and a.prepared == b.prepared and
      (BUG == "value" or a.value == b.value) and a.protocol == b.protocol and
      (BUG == "ancestor" or a.ancestor == b.ancestor) and
      (BUG == "observer" or a.observer == b.observer)
  pure def closed(v: View): bool = v.checker == 10 and v.observer == -1 and
    (v.prepared or (v.protocol == -1 and v.ancestor == -1))
  action init = {
    nondet mode = Set(0,1,2,3,4,5,6,7,8).oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    val view = {checker: 10, revision: 0, instance: 10, prepared: true, value: 23,
                protocol: 99, ancestor: -1, observer: -1}
    all { s' = {phase: 0, old: view, live: view, mode: mode, source: 0,
      priorCallback: false, guarded: false, eligible: false, called: false,
      owner: if (BUG == "parent") 1 else 2, requiredA: a, requiredB: b,
      stalePrefix: mode == 7, fault: -1, accepted: false} }
  }
  action mutate = all { s.phase == 0,
    s' = s.with("phase",1)
      .with("live", if (s.mode == 1) s.live.with("instance",-1).with("prepared",false)
         else if (s.mode == 2) s.live.with("checker",11)
         else if (s.mode == 3) s.live.with("observer",77)
         else if (s.mode == 4) s.live.with("ancestor",88) else if (s.mode == 8) s.live.with("value",24) else s.live)
      .with("source", if (s.mode == 5 or s.mode == 6) 1 else 0)
      // mode 6 installs, calls, and restores an observer before the next capture.
      .with("priorCallback", s.mode == 6) }
  action guard = all { s.phase == 1,
    s' = s.with("phase", if (matches(s.old,s.live)) 2 else 9)
      .with("guarded",matches(s.old,s.live)).with("eligible",closed(s.old)) }
  action check = {
    val called = s.live.checker != 10 or s.live.observer != -1 or
      (not(s.live.prepared) and (s.live.protocol != -1 or s.live.ancestor != -1))
    val source = if (called) 1 else s.source
    val checkedSource = if (BUG == "source") 0 else source
    val prefixFailed = s.stalePrefix and BUG != "prefix"
    all { s.phase == 2,
      s' = s.with("phase",9).with("called",called).with("source",source)
        .with("fault", if (prefixFailed) 0 else if (s.stalePrefix) 1
                       else if (checkedSource != 0) 2 else -1)
        .with("accepted", not(s.stalePrefix) and checkedSource == 0 and
          (BUG == "parent" or s.owner == 2) and s.requiredA and s.requiredB) }
  }
  action terminal = all { s.phase == 9, s' = s }
  action step = any { mutate, guard, check, terminal }
  val ChangedRejected = not(s.guarded) or s.old == s.live
  val NoOpaque = not(s.guarded and s.eligible) or not(s.called)
  val SourcesCurrent = not(s.accepted) or s.source == 0
  val ReceiverIdentity = not(s.accepted) or s.owner == 2
  val TwoRequirements = not(s.accepted) or (s.requiredA and s.requiredB)
  val OrderedDiagnostic = s.phase != 9 or not(s.guarded and s.stalePrefix) or s.fault == 0
  val NoInterveningCallback = not(s.guarded) or not(s.priorCallback)
  val RejectAll = not(s.accepted)
  val safety = ChangedRejected and NoOpaque and SourcesCurrent and ReceiverIdentity and
    TwoRequirements and OrderedDiagnostic
}
module SnapshotEntry { import SnapshotEntryModel(BUG = "none").* }
