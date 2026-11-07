// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReturnTailModel {
  const BUG: str
  type State = {phase: int, mode: str, a: bool, b: bool, owner: int,
    receiver: int, candidate: int, external: int, first: int, second: int,
    replayRevision: int, firstAtRead: int, secondAtRead: int, fault: int,
    accepted: bool, parentPort: int, configPort: int, planPort: int}
  var s: State
  action init = {
    nondet mode = Set("stable","context","replay","receiver","candidate","external","both","earlierFile").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, mode: mode, a: a, b: b, owner: if (BUG == "parent") 1 else 2,
      receiver: 0, candidate: 0, external: 0, first: 0, second: 0,
      replayRevision: -1, firstAtRead: -1, secondAtRead: -1, fault: -1,
      accepted: false, parentPort: 5432, configPort: 5433, planPort: 5433}}
  }
  action early = all {s.phase == 0,
    s' = s.with("phase",1).with("external",if (s.mode == "context" or s.mode == "replay") 1 else 0)}
  action mop = {
    val revision = s.receiver + s.candidate + s.external
    all {s.phase == 1, s' = s.with("phase",2).with("replayRevision",revision)
      .with("fault",if (revision != 0 and BUG != "skipReplay") 1 else -1)}
  }
  // Actual return-currentness/file-read callback, after the last MOP sweep.
  action firstRead = {
    val open = s.fault == -1
    val receiver = if (open and s.mode == "receiver") 1 else s.receiver
    val candidate = if (open and s.mode == "candidate") 1 else s.candidate
    val external = if (open and (s.mode == "external" or s.mode == "both")) 1 else s.external
    val first = if (open and s.mode == "both") 1 else s.first
    val fault = if (not(open)) s.fault
                else if (BUG == "prefix" and s.mode == "both") 1
                else if (first != 0 and BUG != "skipFile") 0 else -1
    all {s.phase == 2,
      s' = s.with("phase",3).with("receiver",receiver).with("candidate",candidate)
        .with("external",external).with("first",first).with("fault",fault)
        .with("configPort",if (open and s.mode == "candidate") 5440 else s.configPort)
        .with("firstAtRead",if (open) first else -1)}
  }
  // Checking second leaves the already compared first file mutable.
  action secondRead = all {s.phase == 3,
    s' = s.with("phase",4)
      .with("first",if (s.fault == -1 and s.mode == "earlierFile") 1 else s.first)
      .with("secondAtRead",if (s.fault == -1) s.second else -1)}
  action finish = all {s.phase == 4,
    s' = s.with("phase",5).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b) and (BUG == "parent" or s.owner == 2))}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {early, mop, firstRead, secondRead, finish, terminal}
  val ReplayWasCurrent = not(s.accepted) or s.replayRevision == 0
  val FilesMatchedWhenRead = not(s.accepted) or (s.firstAtRead == 0 and s.secondAtRead == 0)
  val RequirementsWereChecked = not(s.accepted) or (s.a and s.b)
  val ChildIdentity = not(s.accepted) or s.owner == 2
  val ParentIsolated = s.parentPort == 5432
  val DiagnosticOrder = s.phase < 3 or s.mode != "both" or s.fault == 0
  // These stronger RETURN claims are intentionally false for the actual path.
  val ObjectsCurrentAtReturn = not(s.accepted) or (s.receiver == 0 and s.candidate == 0 and s.external == 0)
  val SourcesCurrentAtReturn = not(s.accepted) or (s.first == 0 and s.second == 0)
  val PlanMatchesAtReturn = not(s.accepted) or s.configPort == s.planPort
  val RejectAll = not(s.accepted)
  val recordedChecks = ReplayWasCurrent and FilesMatchedWhenRead and RequirementsWereChecked and
    ChildIdentity and ParentIsolated and DiagnosticOrder
}
module ReturnTail {import ReturnTailModel(BUG = "none").*}
