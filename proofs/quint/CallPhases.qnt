// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CallPhasesModel {
  const BUG: str
  type State = {phase: int, cold: bool, nested: bool, target: str,
    sourceChange: bool, requiredA: bool, requiredB: bool, owner: int,
    methodFrame: bool, callerFrame: bool, acquired: int, invoked: int,
    root: int, demand: int, source: int, blocked: bool, accepted: bool, fault: int}
  var s: State
  action init = {
    nondet cold = Set(false,true).oneOf()
    nondet nested = Set(false,true).oneOf()
    nondet target = Set("stable","receiver","external").oneOf()
    nondet source = Set(false,true).oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, cold: cold, nested: nested, target: target,
      sourceChange: source, requiredA: a, requiredB: b,
      owner: if (BUG == "parent") 1 else 2, methodFrame: false,
      callerFrame: nested, acquired: 0, invoked: 0, root: 0, demand: 0,
      source: 0, blocked: false, accepted: false, fault: -1}}
  }
  action lookup = all {s.phase == 0,
    s' = s.with("phase",1).with("methodFrame",s.cold)
      .with("acquired",if (s.cold) 1 else 0)}
  // Native .call applies the returned procedure AFTER .get has returned.
  // An enclosing preview frame survives; the operation lookup frame does not.
  action body = all {s.phase == 1,
    s' = s.with("phase",2).with("methodFrame",BUG == "leak" and s.cold)
      .with("callerFrame",s.nested and BUG != "dropCaller").with("invoked",1)}
  action mutate = all {s.phase == 2,
    s' = s.with("phase",3)
      .with("blocked",s.target == "receiver" and (s.callerFrame or s.methodFrame))
      .with("root",if (s.target == "receiver" and not(s.callerFrame) and not(s.methodFrame)) 1 else 0)
      .with("demand",if (s.target == "external") 1 else 0)
      .with("source",if (s.sourceChange) 1 else 0)}
  action check = {
    val reads = s.root == 0 and (BUG == "lookupOnly" or s.demand == 0)
    val fault = if (BUG == "prefix" and not(reads)) 1
                else if (s.source != 0) 0 else if (not(reads)) 1 else -1
    all {s.phase == 3,
      s' = s.with("phase",4).with("fault",if (s.blocked) 2 else fault)
        .with("accepted",(BUG == "acceptVeto" or not(s.blocked)) and reads and s.source == 0 and s.requiredA and
          (BUG == "dropB" or s.requiredB) and (BUG == "parent" or s.owner == 2))}
  }
  action terminal = all {s.phase == 4, s' = s}
  action step = any {lookup, body, mutate, check, terminal}
  val LookupShape = s.phase != 1 or (s.methodFrame == s.cold and s.acquired == (if (s.cold) 1 else 0))
  val MethodUnwound = s.phase < 2 or not(s.methodFrame)
  val BodyRuns = s.phase < 2 or s.invoked == 1
  val NestedProtected = s.phase < 3 or not(s.nested) or s.target != "receiver" or s.root == 0
  val TopLevelCanEdit = s.phase < 3 or s.nested or s.target != "receiver" or s.root == 1
  val CurrentPlan = not(s.accepted) or (s.root == 0 and s.demand == 0 and s.source == 0)
  val TwoRequirements = not(s.accepted) or (s.requiredA and s.requiredB)
  val ReceiverIdentity = not(s.accepted) or s.owner == 2
  val OrderedDiagnostic = s.phase != 4 or s.blocked or s.source == 0 or s.fault == 0
  val FailedBodyRejected = not(s.blocked) or not(s.accepted)
  val NoBodyMutation = s.phase < 3 or (s.root == 0 and s.demand == 0)
  val RejectAll = not(s.accepted)
  val safety = LookupShape and MethodUnwound and BodyRuns and NestedProtected and
    TopLevelCanEdit and FailedBodyRejected and CurrentPlan and TwoRequirements and ReceiverIdentity and OrderedDiagnostic
}
module CallPhases {import CallPhasesModel(BUG = "none").*}
