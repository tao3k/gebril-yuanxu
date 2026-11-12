// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module AdmissionBodyModel {
  const BUG: str
  type State = {phase: int, mode: str, childSource: bool, a: bool, b: bool,
    rootCount: int, childCount: int, changed: bool, collected: bool,
    childRejected: bool, source: int, accepted: bool, fault: int,
    parentPort: int, childPort: int, owner: int}
  var s: State
  action init = {
    nondet mode = Set("stable","receiver","candidate","external","both").oneOf()
    nondet child = Set(false,true).oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    // A prior successful call warmed the function; this is another call, not
    // reuse of an earlier accepted receipt. Counts are obligation invocations.
    all {s' = {phase: 0, mode: mode, childSource: child, a: a, b: b,
      rootCount: 1, childCount: 1, changed: false, collected: false,
      childRejected: false, source: 0, accepted: false, fault: -1,
      parentPort: 5432, childPort: 5433, owner: if (BUG == "parent") 1 else 2}}
  }
  action body = all {s.phase == 0,
    s' = s.with("phase",1).with("childCount",if (BUG == "trustHot") 1 else 2)
      .with("changed",s.mode != "stable" and BUG != "trustHot")
      .with("collected",s.mode != "stable" and BUG != "trustHot" and BUG != "acquisitionOnly")
      .with("source",if (s.mode == "both" and BUG != "trustHot") 1 else 0)}
  action childReturn = all {s.phase == 1,
    s' = s.with("phase",2).with("childRejected",s.childSource and s.changed and BUG != "skipChild")
      .with("rootCount",if (s.childSource and s.changed and BUG != "skipChild") 1
                        else if (BUG == "trustHot") 1 else 2)}
  action sourceCheck = all {s.phase == 2,
    s' = s.with("phase",3).with("fault",if (s.childRejected) 2
      else if (s.source != 0 and BUG != "prefix") 0 else -1)}
  action replay = all {s.phase == 3,
    s' = s.with("phase",4).with("fault",if (s.fault != -1) s.fault
      else if (s.collected and s.changed and BUG != "skipReplay") 1
      else if (s.source != 0) 0 else -1)}
  action finish = all {s.phase == 4,
    s' = s.with("phase",5).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b) and (BUG == "parent" or s.owner == 2))}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {body, childReturn, sourceCheck, replay, finish, terminal}
  val HotBodies = s.phase < 1 or s.childCount == 2
  val ChildOwnReject = s.phase < 2 or not(s.childSource and s.changed) or s.childRejected
  val ObservedCurrent = not(s.accepted) or not(s.changed)
  val TwoRequirements = not(s.accepted) or (s.a and s.b)
  val ChildIdentity = not(s.accepted) or s.owner == 2
  val ParentIsolated = s.parentPort == 5432 and s.childPort == 5433
  val DiagnosticOrder = s.phase < 4 or s.childRejected or s.source == 0 or s.fault == 0
  val NoWritesBeforeReject = not(s.changed)
  val RejectAll = not(s.accepted)
  val safety = HotBodies and ChildOwnReject and ObservedCurrent and TwoRequirements and
    ChildIdentity and ParentIsolated and DiagnosticOrder
}
module AdmissionBody {import AdmissionBodyModel(BUG = "none").*}
