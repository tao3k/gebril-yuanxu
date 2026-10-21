// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Derived raw-state eligibility; no producer/user `pure` marker exists.
module ReadOnlyEntryModel {
  const BUG: str
  type State = {phase: int, kind: int, checker: int, revision: int, instance: int,
    table: int, anchor: int, prepared: bool, protocol: int, observer: int,
    sealed: bool, c3Error: bool, foreignReturn: bool, conflict: bool,
    eligible: bool, source: int, candidate: int, planOwner: int,
    initialSource: int, calledOpaque: bool, fault: int, accepted: bool}
  var s: State
  pure def current(state: State): bool = state.revision == 0 and
    (if (state.kind == 1) state.anchor == 23
     else state.instance == 10 and state.table == 7)
  pure def inspect(state: State): bool =
    (state.checker == 10 or BUG == "checker") and
    (not(current(state)) or
      ((state.prepared or state.protocol == -1 or
        (BUG == "sealed" and state.sealed) or
        (BUG == "revision" and state.revision == 0)) and
       (state.observer == -1 or BUG == "observer"))) and
    // The window includes JSON prefix checks, so its observer must also be closed.
    (state.observer == -1 or BUG == "observer")
  action init = {
    nondet sample = Set(0, 1, 2, 3, 4, 5, 6, 7, 8).oneOf()
    nondet conflict = Set(false, true).oneOf()
    nondet c3Error = Set(false, true).oneOf()
    nondet foreignReturn = Set(false, true).oneOf()
    all { s' = {phase: 0, kind: if (sample >= 1 and sample <= 3) 1 else 0,
      checker: if (sample == 6) 11 else 10,
      revision: if (sample == 3 or sample == 8) 1 else 0,
      instance: if (sample == 2 or sample == 3) -1 else 10,
      table: if (sample == 2 or sample == 3) -1 else 7,
      anchor: 23, prepared: not(Set(2, 3, 4, 5).contains(sample)),
      protocol: if (sample == 4) -1 else 99,
      observer: if (sample == 7) 77 else -1,
      sealed: Set(1, 2, 3).contains(sample), c3Error: c3Error,
      foreignReturn: foreignReturn, conflict: conflict, eligible: false,
      source: if (sample == 8) 1 else 0, candidate: 2,
      planOwner: if (BUG == "parent") 1 else 2,
      initialSource: if (sample == 8) 1 else 0,
      calledOpaque: false, fault: -1, accepted: false} }
  }
  action classify = all {
    s.phase == 0,
    s' = s.with("phase", 1).with("eligible", inspect(s))
          // An explicit later scope rebind makes a previously closed plan stale.
          .with("observer", if (BUG == "scopeReuse") 77 else s.observer)
  }
  action prefix = {
    nondet effect = Set(0, 1, 2).oneOf()
    val source = if (s.observer != -1 and effect == 1) 1 else s.source
    all { s.phase == 1,
      s' = s.with("phase", if (source != 0 and BUG != "dropPrefix") 9 else 2)
            .with("fault", if (source != 0 and BUG != "dropPrefix") 0 else -1)
            .with("source", source)
            .with("candidate", if (s.observer != -1 and effect == 2) 1 else s.candidate)
            .with("calledOpaque", s.observer != -1) }
  }
  action recordCheck = {
    nondet effect = Set(0, 1, 2).oneOf()
    val foreign = s.checker != 10
    val anchorCalled = BUG == "anchorExecute" and s.kind == 1
    val called = foreign or anchorCalled
    val valid = if (foreign) s.foreignReturn else current(s)
    all { s.phase == 2,
      s' = s.with("phase", if (valid) 3 else 9)
            .with("fault", if (valid) -1 else 1)
            .with("calledOpaque", s.calledOpaque or called)
            .with("source", if (called and effect == 1) 1 else s.source)
            .with("candidate", if (called and effect == 2) 1 else s.candidate) }
  }
  action metadata = {
    nondet effect = Set(0, 1, 2).oneOf()
    val failed = not(s.prepared) and s.c3Error
    val hook = not(s.prepared) and not(failed) and s.protocol != -1
    all { s.phase == 3,
      s' = s.with("phase", if (failed) 9 else 4)
            .with("fault", if (failed) 2 else -1)
            .with("calledOpaque", s.calledOpaque or hook)
            .with("source", if (hook and effect == 1) 1 else s.source)
            .with("candidate", if (hook and effect == 2) 1 else s.candidate) }
  }
  action sourceCheck = {
    nondet effect = Set(0, 1, 2).oneOf()
    val source = if (s.observer != -1 and effect == 1) 1 else s.source
    val candidate = if (s.observer != -1 and effect == 2) 1 else s.candidate
    val sourceOK = if (s.eligible or BUG == "sourceReuse") s.initialSource == 0 else source == 0
    val ownerOK = BUG == "parent" or (s.planOwner == 2 and candidate == 2)
    all { s.phase == 4,
      s' = s.with("phase", 9).with("calledOpaque", s.calledOpaque or s.observer != -1)
            .with("source", source).with("candidate", candidate)
            .with("fault", if (sourceOK) -1 else 0)
            .with("accepted", sourceOK and ownerOK and not(s.conflict)) }
  }
  action terminal = all { s.phase == 9, s' = s }
  action step = any { classify, prefix, recordCheck, metadata, sourceCheck, terminal }
  val NoOpaque = not(s.eligible) or not(s.calledOpaque)
  val Protected = not(s.eligible) or (s.source == s.initialSource and s.candidate == 2)
  val SourcesCurrent = not(s.accepted) or s.source == 0
  val ReceiverIdentity = not(s.accepted) or (s.planOwner == 2 and s.candidate == 2)
  val TwoRequirements = not(s.accepted) or not(s.conflict)
  val OrderedDiagnostic = s.phase != 9 or s.initialSource == 0 or s.fault == 0
  val RejectAll = not(s.accepted)
  val safety = NoOpaque and Protected and SourcesCurrent and ReceiverIdentity and
    TwoRequirements and OrderedDiagnostic
}
module ReadOnlyEntry {
  import ReadOnlyEntryModel(BUG = "none").*
}
