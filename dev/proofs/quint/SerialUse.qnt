// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SerialUseModel {
  const BUG: str
  // Active means an actual cold computation frame, never a caller purity flag.
  type State = {phase: int, cold: bool, mode: str, root: int, demand: int,
    source: int, prepared: bool, used: bool, staleUse: bool, accepted: bool,
    requiredA: bool, requiredB: bool, owner: int, fault: int}
  var s: State
  pure def current(x: State): bool = x.root == 0 and x.demand == 0
  action init = {
    nondet cold = Set(false,true).oneOf()
    nondet mode = Set("stable","affected","demand","source","lateSource","abaSource","both").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all { s' = {phase: 0, cold: cold, mode: mode, root: 0, demand: 0, source: 0,
      prepared: false, used: false, staleUse: false, accepted: false,
      requiredA: a, requiredB: b, owner: if (BUG == "parent") 1 else 2, fault: -1} }
  }
  action prepare = all { s.phase == 0,
    s' = s.with("phase",1).with("prepared",s.requiredA and s.requiredB and s.owner == 2) }
  action intervene = all { s.phase == 1,
    s' = s.with("phase",2)
      .with("root",if (s.mode == "affected" and (not(s.cold) or BUG == "noGuard")) 1 else 0)
      .with("demand",if ((s.mode == "demand" or s.mode == "both")) 1 else 0)
      // Monotonic external version abstracts a provider CAS precondition, not a MOP field.
      .with("source",if (s.mode == "source" or s.mode == "both") 1 else if (s.mode == "abaSource") 2 else 0) }
  action use = all { s.phase == 2,
    s' = s.with("phase",3).with("used",s.prepared)
      .with("staleUse",s.prepared and (not(current(s)) or s.source != 0)) }
  action check = {
    val sourceOK = s.source == 0
    val readOK = if (BUG == "omitDemand") s.root == 0 else current(s)
    val fault = if (BUG == "prefix" and not(readOK)) 1
                else if (not(sourceOK)) 0 else if (not(readOK)) 1 else -1
    all { s.phase == 3, s' = s.with("phase",4).with("fault",fault)
      .with("accepted",sourceOK and readOK and s.requiredA and
        (BUG == "dropB" or s.requiredB) and (BUG == "parent" or s.owner == 2)) }
  }
  action late = all { s.phase == 4,
    s' = s.with("phase",5).with("source",if (s.mode == "lateSource") 1 else s.source) }
  // This atomic comparison+commit belongs to the external authority. Local check
  // alone cannot implement it; BUG=localOnly shows the missing guarantee.
  action commit = all { s.phase == 5,
    s' = s.with("phase",6).with("accepted",s.accepted and
      (BUG == "localOnly" or s.source == 0)) }
  action terminal = all { s.phase == 6, s' = s }
  action step = any { prepare, intervene, use, check, late, commit, terminal }
  val ActiveProtected = not(s.cold) or s.mode != "affected" or s.root == 0
  val TwoRequirements = not(s.accepted) or (s.requiredA and s.requiredB)
  val ReceiverIdentity = not(s.accepted) or s.owner == 2
  val ReadCurrent = not(s.accepted) or current(s)
  val OrderedDiagnostic = s.phase < 4 or (s.mode != "source" and s.mode != "both") or s.fault == 0
  val ConditionalCommit = s.phase != 6 or not(s.accepted) or s.source == 0
  val ColdFreezesAll = not(s.cold) or not(s.staleUse)
  val RejectAll = not(s.accepted)
  val safety = ActiveProtected and TwoRequirements and ReceiverIdentity and ReadCurrent and
    OrderedDiagnostic and ConditionalCommit
}
module SerialUse { import SerialUseModel(BUG = "none").* }
