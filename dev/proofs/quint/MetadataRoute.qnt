// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// A callback-free, direct checked call, not protection from other threads/FFI.
module MetadataRouteModel {
  const BUG: str
  type State = {phase: int, kind: str, ref: int, instanceRef: int, hash: int,
    test: int, backend: int, a: bool, b: bool, fault: int, entryOK: bool,
    calls: int, external: int, issued: bool, accepted: bool,
    parent: int, config: int, plan: int}
  var s: State
  action init = {
    nondet kind = Set("native","ref","instance","hash","test","backend",
      "late","aba","genuineMiss","forgedMiss","earlierSource").oneOf()
    nondet a = Set(false,true).oneOf()
    nondet b = Set(false,true).oneOf()
    all {s' = {phase: 0, kind: kind, ref: if (kind == "ref") 1 else 0,
      instanceRef: if (kind == "instance") 1 else 0,
      hash: if (kind == "hash") 1 else 0, test: if (kind == "test") 1 else 0,
      backend: if (kind == "backend") 1 else 0, a: a, b: b,
      fault: -1, entryOK: false, calls: 0, external: 0,
      issued: kind != "forgedMiss", accepted: false,
      parent: 5432, config: 5433, plan: 5433}}
  }
  val fullRoute = s.ref == 0 and s.instanceRef == 0 and s.hash == 0 and
    s.test == 0 and s.backend == 0
  val selectedRoute = if (BUG == "refOnly") s.ref == 0 and s.instanceRef == 0
    else if (BUG == "readsOnly") s.ref == 0 and s.hash == 0 and s.test == 0 and s.backend == 0
    else fullRoute
  action source = all {s.phase == 0,
    s' = s.with("phase",1).with("fault",if (s.kind == "earlierSource") 0 else -1)}
  action entry = all {s.phase == 1,
    s' = s.with("phase",2).with("entryOK",selectedRoute)}
  // The qualified helper has no extension callback argument in this interval.
  // Mutants open such an interval; a native pointer comparison is not a fence.
  action gap = all {s.phase == 2,
    s' = s.with("phase",3).with("ref",
      if ((BUG == "entryOnly" and s.kind == "late") or
          (BUG == "endpoint" and s.kind == "aba")) 1 else s.ref)}
  action invoke = {
    val allowed = if (BUG == "entryOnly" or BUG == "endpoint") s.entryOK else selectedRoute
    val foreign = s.fault == -1 and allowed and
      (s.ref != 0 or s.instanceRef != 0 or s.hash != 0 or s.test != 0)
    val lookupFault = s.fault == -1 and allowed and (s.hash != 0 or s.test != 0 or s.backend != 0)
    all {s.phase == 3,
      s' = s.with("phase",4).with("fault",
        if (s.fault != -1) s.fault else if (not(allowed)) 1 else if (lookupFault) 2 else -1)
        .with("calls",if (foreign) 1 else 0).with("external",if (foreign) 1 else 0)
        .with("ref",if (BUG == "endpoint" and s.kind == "aba") 0 else s.ref)}
  }
  action finish = all {s.phase == 4,
    s' = s.with("phase",5).with("accepted",s.fault == -1 and s.a and
      (BUG == "dropB" or s.b) and (BUG != "endpoint" or fullRoute))
      .with("plan",if (BUG == "parent") s.parent else s.plan)}
  action terminal = all {s.phase == 5, s' = s}
  action step = any {source, entry, gap, invoke, finish, terminal}
  val NoForeignCalls = s.calls == 0
  val Issuance = not(s.accepted) or s.issued
  val TwoRequirements = not(s.accepted) or (s.a and s.b)
  val FinalPlan = not(s.accepted) or s.plan == s.config
  val ParentIsolated = s.parent == 5432
  val SourceFirst = s.phase == 0 or s.kind != "earlierSource" or s.fault == 0
  val RejectAll = not(s.accepted)
  // Issuance is deliberately not inferred from this route safety law.
  val safety = NoForeignCalls and TwoRequirements and FinalPlan and ParentIsolated and SourceFirst
}
module MetadataRoute { import MetadataRouteModel(BUG = "none").* }
