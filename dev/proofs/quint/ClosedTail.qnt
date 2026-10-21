// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Qualification-only dispatcher: reject every opaque observer before invoking it.
module ClosedTailModel {
  const BUG: str
  type State = {phase: int, mode: str, a: bool, b: bool, owner: int,
    receiver: int, candidate: int, external: int, first: int, second: int,
    firstAtRead: int, secondAtRead: int, fault: int, accepted: bool,
    foreignCalls: int, refused: bool, observer: bool, parentPort: int, configPort: int, planPort: int}
  var s: State
  action init = {
    nondet mode = Set("stable","receiver","candidate","external","earlierFile",
                      "benign","cleanup","outsideWriter","bothBefore","objectBefore").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, mode: mode, a: a, b: b,
      owner: if (BUG == "parent") 1 else 2,
      receiver: 0, candidate: 0, external: 0, first: 0, second: 0,
      firstAtRead: -1, secondAtRead: -1, fault: -1, accepted: false,
      foreignCalls: 0, refused: false,
      observer: Set("receiver","candidate","external","earlierFile","benign","cleanup").contains(mode), parentPort: 5432, configPort: 5433, planPort: 5433}}
  }
  // Already established native ordering: source failure before stale-object fault.
  action early = all {s.phase == 0,
    s' = s.with("phase",1)
      .with("external",if (s.mode == "bothBefore" or s.mode == "objectBefore") 1 else 0)
      .with("first",if (s.mode == "bothBefore") 1 else 0)
      .with("fault",if (s.mode == "bothBefore") (if (BUG == "prefix") 1 else 0)
                     else if (s.mode == "objectBefore") 1 else -1)}
  // Restriction starts before replay, thereby also owning its cache-exit tail.
  action mop = {
    val denied = s.fault == -1 and s.observer and BUG != "admitForeign" and BUG != "returnOnly"
    all {s.phase == 1, s' = s.with("phase",2)
      .with("fault",if (denied) 2 else s.fault).with("refused",denied)}
  }
  val opaque = s.observer
  action firstRead = {
    val open = s.fault == -1
    // Project the cache-exit callback and its self-removal before first file read.
    val exitAttack = open and s.mode == "cleanup" and
                     (BUG == "admitForeign" or BUG == "returnOnly")
    val denied = open and opaque and not(exitAttack) and BUG != "admitForeign"
    val invoked = exitAttack or (open and opaque and not(denied))
    all {s.phase == 2,
      s' = s.with("phase",3)
        .with("fault",if (denied) 2 else s.fault).with("refused",s.refused or denied)
        .with("observer",if (exitAttack) false else s.observer)
        .with("foreignCalls",if (invoked) 1 else 0)
        .with("receiver",if (invoked and s.mode == "receiver") 1 else s.receiver)
        .with("candidate",if (invoked and s.mode == "candidate") 1 else s.candidate)
        .with("external",if (invoked and (s.mode == "external" or s.mode == "cleanup")) 1 else s.external)
        .with("configPort",if (invoked and s.mode == "candidate") 5440 else s.configPort)
        .with("firstAtRead",if (open and not(denied)) s.first else -1)}
  }
  action secondRead = all {s.phase == 3,
    s' = s.with("phase",4)
      .with("first",if (s.fault == -1 and
                        (s.mode == "outsideWriter" or
                         (s.mode == "earlierFile" and BUG == "admitForeign"))) 1 else s.first)
      .with("secondAtRead",if (s.fault == -1) s.second else -1)}
  action finish = all {s.phase == 4,
    s' = s.with("phase",5).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b) and (BUG == "parent" or s.owner == 2))}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {early, mop, firstRead, secondRead, finish, terminal}
  val NoForeignCalls = s.foreignCalls == 0
  val RefusedBeforeEffects = not(s.refused) or
    (not(s.accepted) and s.foreignCalls == 0 and s.receiver == 0 and s.candidate == 0 and s.external == 0)
  val ObjectsCurrent = not(s.accepted) or (s.receiver == 0 and s.candidate == 0 and s.external == 0)
  // Environment-owned writes remain explicit transitions, not a manual purity flag.
  val SourcesClosedInternally = not(s.accepted) or s.mode == "outsideWriter" or
    (s.first == 0 and s.second == 0)
  val SourcesCurrent = not(s.accepted) or (s.first == 0 and s.second == 0)
  val TwoRequirements = not(s.accepted) or (s.a and s.b)
  val ChildIdentity = not(s.accepted) or s.owner == 2
  val ParentIsolated = s.parentPort == 5432
  val PlanMatches = not(s.accepted) or s.configPort == s.planPort
  val OrderedDiagnostic = s.phase == 0 or s.mode != "bothBefore" or s.fault == 0
  val RejectAll = not(s.accepted)
  val safety = NoForeignCalls and RefusedBeforeEffects and ObjectsCurrent and
    SourcesClosedInternally and TwoRequirements and ChildIdentity and ParentIsolated and
    PlanMatches and OrderedDiagnostic
}
module ClosedTail {import ClosedTailModel(BUG = "none").*}
