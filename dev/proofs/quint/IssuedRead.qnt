// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module IssuedReadModel {
  const BUG: str
  type State = {phase: int, kind: str, token: int, birthToken: int,
    value: int, birthValue: int, checker: int, birthChecker: int,
    birthNative: bool, registered: int, presented: int, childIssued: bool, route: int, fault: int,
    calls: int, observed: int, missCached: bool, nativeCreated: bool,
    a: bool, b: bool, accepted: bool, parent: int, config: int, plan: int}
  var s: State
  action init = {
    nondet kind = Set("persistent","miss","copy","borrow","payload","child",
      "displaced","route","callbackChecker","callbackRoute","earlierSource","rawBirth").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, kind: kind,
      token: if (Set("copy","borrow","rawBirth").contains(kind)) 2 else 1,
      birthToken: if (kind == "copy") 0 else if (kind == "rawBirth" and BUG == "rawBirth") 2 else 1,
      value: if (kind == "payload") 5440 else 5433, birthValue: 5433,
      checker: 0, birthChecker: 0, birthNative: kind != "copy",
      registered: if (kind == "copy") 0 else 1, presented: if (kind == "displaced") 2 else 1,
      childIssued: kind != "child", route: if (kind == "route") 1 else 0,
      fault: -1, calls: 0, observed: 0, missCached: false,
      nativeCreated: not(Set("copy","borrow","rawBirth").contains(kind)),
      a: a, b: b, accepted: false, parent: 5432, config: 5433, plan: 5433}}
  }
  val rootIssued = s.birthNative and s.registered == s.presented and s.token == s.birthToken and
    s.value == s.birthValue and s.checker == s.birthChecker
  val wholeIssued = rootIssued and (BUG == "rootOnly" or s.childIssued)
  action source = all {s.phase == 0,
    s' = s.with("phase",1).with("fault",if (s.kind == "earlierSource") 0 else -1)}
  action authenticate = all {s.phase == 1,
    s' = s.with("phase",2).with("fault",
      if (s.fault != -1) s.fault else if (not(wholeIssued) and BUG != "noBirth") 1 else -1)
      .with("missCached",BUG == "registerMiss" and s.kind == "miss")}
  action firstCheck = {
    val open = s.fault == -1
    val invokeForeign = open and s.route != 0 and BUG == "noRoute"
    all {s.phase == 2,
      s' = s.with("phase",3).with("fault",
        if (open and s.route != 0 and BUG != "noRoute") 2 else s.fault)
        .with("calls",if (invokeForeign) 1 else s.calls)
        .with("observed",if (open and (s.route == 0 or BUG == "noRoute")) 1 else 0)}
  }
  // Generic MOP observers remain callbacks. Their persistent tampering must be
  // refused before a later checker call, not certified as a read-only history.
  action callback = all {s.phase == 3,
    s' = s.with("phase",4)
      .with("checker",if (s.fault == -1 and s.kind == "callbackChecker") 1 else s.checker)
      .with("route",if (s.fault == -1 and s.kind == "callbackRoute") 1 else s.route)}
  action finalCheck = all {s.phase == 4,
    s' = s.with("phase",5).with("fault",
      if (s.fault != -1 or BUG == "skipFinal") s.fault
      else if (not(wholeIssued) and BUG != "noBirth") 1 else if (s.route != 0) 2 else -1)}
  action finish = all {s.phase == 5,
    s' = s.with("phase",6).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b)).with("plan",if (BUG == "parent") s.parent else s.plan)}
  action terminal = all {s.phase == 6, s' = s}
  action step = any {source, authenticate, firstCheck, callback, finalCheck, finish, terminal}
  val NoForgery = not(s.accepted) or s.nativeCreated
  val WholeClosureBeforeObserve = s.observed == 0 or s.childIssued
  val NoForeignCheckerCalls = s.calls == 0
  val FinalAuthenticity = not(s.accepted) or (rootIssued and s.childIssued and s.route == 0)
  val MissNotCached = not(s.missCached)
  val TwoRequirements = not(s.accepted) or (s.a and s.b)
  val FinalPlan = not(s.accepted) or s.plan == s.config
  val ParentIsolated = s.parent == 5432
  val SourceFirst = s.phase == 0 or s.kind != "earlierSource" or s.fault == 0
  val RejectAll = not(s.accepted)
  val safety = NoForgery and WholeClosureBeforeObserve and NoForeignCheckerCalls and
    FinalAuthenticity and MissNotCached and TwoRequirements and FinalPlan and ParentIsolated and SourceFirst
}
module IssuedRead { import IssuedReadModel(BUG = "none").* }
