// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Identity and current receiver-table membership, not a claimed purity bit.
module CheckerOriginModel {
  const BUG: str
  type State = {phase: int, kind: str, checker: int, record: int, table: int,
    dependencyChecker: int, a: bool, b: bool, fault: int, calls: int,
    external: int, accepted: bool, refused: bool, issued: bool,
    parent: int, config: int, plan: int}
  var s: State
  action init = {
    nondet kind = Set("native","copy","bootstrap","miss","foreign","nested","rawTable","metadataHook","earlierSource").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, kind: kind,
      checker: if (kind == "foreign") 1 else 0,
      record: if (Set("copy","bootstrap","miss","foreign","rawTable").contains(kind)) 2 else 1,
      table: if (kind == "rawTable") 2 else 1,
      dependencyChecker: if (kind == "nested") 1 else 0,
      a: a, b: b, fault: -1, calls: 0, external: 0,
      accepted: false, refused: false,
      issued: not(Set("copy","bootstrap","miss","foreign","rawTable").contains(kind)),
      parent: 5432, config: 5433, plan: 5433}}
  }
  action source = all {s.phase == 0,
    s' = s.with("phase",1).with("fault",if (s.kind == "earlierSource") 0 else -1)}
  action preflight = {
    val rootOK = (BUG == "invokeAny" or s.checker == 0) and
      (BUG == "identityOnly" or BUG == "invokeAny" or s.record == s.table)
    val depsOK = BUG == "rootOnly" or BUG == "invokeAny" or s.dependencyChecker == 0
    val deny = s.fault == -1 and not(rootOK and depsOK)
    all {s.phase == 1, s' = s.with("phase",2)
      .with("fault",if (deny) 1 else s.fault).with("refused",deny)}
  }
  action check = {
    val foreign = s.fault == -1 and (s.checker == 1 or s.dependencyChecker == 1 or s.kind == "metadataHook")
    all {s.phase == 2, s' = s.with("phase",3)
      .with("calls",if (foreign) 1 else 0).with("external",if (foreign) 1 else s.external)}
  }
  action finish = all {s.phase == 3,
    s' = s.with("phase",4).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b)).with("plan",if (BUG == "parent") s.parent else s.plan)}
  action terminal = all {s.phase == 4, s' = s}
  action step = any {source, preflight, check, finish, terminal}
  val NoForeignCalls = s.calls == 0
  val NoForeignCheckerCalls = s.kind == "metadataHook" or NoForeignCalls
  val OwnedAtAdmission = not(s.accepted) or s.record == s.table
  val AuthenticIssuance = not(s.accepted) or s.issued
  val Current = not(s.accepted) or s.external == 0
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ParentIsolated = s.parent == 5432
  val FinalPlan = not(s.accepted) or s.plan == s.config
  val DiagnosticOrder = s.phase == 0 or s.kind != "earlierSource" or s.fault == 0
  val RejectAll = not(s.accepted)
  // A fixed checker can still dispatch an altered runtime HashTable method.
  // The positive law is CONDITIONAL on unchanged native metadata operations.
  // The separate metadataHook model checks and refutes the unconditional law.
  val safety = (s.kind == "metadataHook" or (NoForeignCalls and Current)) and
    OwnedAtAdmission and BothRequirements and ParentIsolated and FinalPlan and DiagnosticOrder
}
module CheckerOrigin { import CheckerOriginModel(BUG = "none").* }
