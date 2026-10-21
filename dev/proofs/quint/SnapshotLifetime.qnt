// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SnapshotLifetimeModel {
  const BUG: str
  type State = {phase: int, mode: str, revision: int, childRevision: int,
    value: int, observer: int, source: int, edits: int, active: Set[int],
    veto: bool, preuse: bool, sent: int, staleUse: bool, priorEffect: bool,
    requiredA: bool, requiredB: bool, owner: int, accepted: bool, fault: int}
  var s: State
  pure def sameCut(state: State): bool = state.value == 1 and state.observer == -1 and
    (BUG == "valueOnly" or (state.revision == 0 and
      (BUG == "receiverOnly" or state.childRevision == 0)))
  action init = {
    nondet mode = Set("idle","editABA","scopeABA","gap","active","afterGuard","sourceAndGap","dependency").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all { s' = {phase: 0, mode: mode, revision: 0, childRevision: 0,
      value: 1, observer: -1, source: 0, edits: 0,
      active: if (mode == "active") Set(1) else Set(), veto: false,
      preuse: false, sent: 0, staleUse: false, priorEffect: false,
      requiredA: a, requiredB: b, owner: if (BUG == "parent") 1 else 2,
      accepted: false, fault: -1} }
  }
  // Capturing and checking the initial cut sees the same actual state.
  action entry = all { s.phase == 0, s' = s.with("phase",1) }
  action mutate = {
    val blocked = s.active.intersect(Set(0,1)).size() > 0
    val edits = if (s.mode == "editABA") 2
                else if (s.mode == "gap" or s.mode == "sourceAndGap" or s.mode == "dependency") 1 else 0
    val rootDelta = if (s.mode == "dependency") 0
                    else if (blocked and BUG == "skipClosure") 1
                    else if (BUG == "duplicate") 2 * edits else edits
    all { s.phase == 1,
      s' = s.with("phase",2).with("veto",blocked).with("edits",edits)
        .with("revision",rootDelta).with("childRevision",edits)
        .with("value",if (edits == 1 and s.mode != "dependency") 2 else 1)
        .with("source",if (s.mode == "scopeABA" or s.mode == "sourceAndGap") 1 else 0)
        .with("priorEffect",s.mode == "scopeABA") }
  }
  action preuse = all { s.phase == 2,
    s' = s.with("phase",3).with("preuse",not(s.veto) and sameCut(s) and s.source == 0 and
      s.requiredA and s.requiredB and s.owner == 2) }
  // An adversarial but supported edit AFTER the last comparison. This is a
  // deterministic interleaving control, not a proof of native parallel safety.
  action gap = all { s.phase == 3,
    s' = if (s.mode == "afterGuard")
      s.with("phase",4).with("revision",1).with("childRevision",1).with("edits",1).with("value",2)
      else s.with("phase",4) }
  action use = all { s.phase == 4,
    s' = s.with("phase",5).with("sent",if (s.preuse) 1 else 0)
      .with("staleUse",s.preuse and not(sameCut(s))) }
  action certify = {
    val sourceOK = BUG == "crossEffect" or s.source == 0
    val current = sameCut(s)
    val requirements = s.requiredA and (BUG == "dropRequirement" or s.requiredB)
    val owner = BUG == "parent" or s.owner == 2
    val fault = if (BUG == "prefix" and not(current)) 1
                else if (not(sourceOK)) 0 else if (not(current)) 1 else -1
    all { s.phase == 5,
      s' = s.with("phase",9).with("fault",fault)
        .with("accepted",not(s.veto) and sourceOK and current and requirements and owner) }
  }
  action terminal = all { s.phase == 9, s' = s }
  action step = any { entry, mutate, preuse, gap, use, certify, terminal }
  val ActiveBlocked = not(s.veto) or (s.revision == 0 and s.childRevision == 0)
  val OncePerOwner = s.phase < 2 or s.veto or
    (s.revision == (if (s.mode == "dependency") 0 else s.edits) and s.childRevision == s.edits)
  val CurrentPlan = not(s.accepted) or
    (s.revision == 0 and s.childRevision == 0 and s.value == 1 and s.observer == -1)
  val SourcesCurrent = not(s.accepted) or s.source == 0
  val TwoRequirements = not(s.accepted) or (s.requiredA and s.requiredB)
  val ReceiverIdentity = not(s.accepted) or s.owner == 2
  val OrderedDiagnostic = s.phase != 9 or s.source == 0 or s.fault == 0
  val EndpointMeansNoEffect = s.phase < 2 or not(sameCut(s)) or not(s.priorEffect)
  val NoStaleUse = not(s.staleUse)
  val RejectAll = not(s.accepted)
  val safety = ActiveBlocked and OncePerOwner and CurrentPlan and SourcesCurrent and
    TwoRequirements and ReceiverIdentity and OrderedDiagnostic
}
module SnapshotLifetime { import SnapshotLifetimeModel(BUG = "none").* }
