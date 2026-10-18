// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Construct registry/environment entries by mint transitions, never by a
// birthNative flag. Handle 3 is an untrusted, self-consistent user closure.
module IssuerProjectionModel {
  const BUG: str
  pure val ids = Set(0, 1, 2, 3)
  type State = {phase: int, kind: str, miss: bool, registry: int -> int,
    owner: int -> int, frozen: int -> int, token: int, presented: int,
    payload: int, cache: Set[int], route: int, revision: int, effects: int,
    checkerCalls: int, first: bool, accepted: bool, a: bool, b: bool,
    planOwner: int, unselected: int}
  var s: State
  action init = {
    nondet kind = Set("native", "fake", "borrowed", "payload", "replaced",
      "closureRestore", "metadataRestore", "metadataStay", "revisionABA").oneOf()
    nondet miss = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, kind: kind, miss: miss, registry: ids.mapBy(_ => 0),
      owner: ids.mapBy(_ => 0), frozen: ids.mapBy(_ => 0), token: 0,
      presented: 0, payload: 5433, cache: Set(), route: 0, revision: 0,
      effects: 0, checkerCalls: 0, first: false, accepted: false, a: a, b: b,
      planOwner: 2, unselected: 0}}
  }
  action mintParent = all {s.phase == 0,
    s' = s.with("phase", 1).with("registry", s.registry.set(1,1))
      .with("owner", s.owner.set(1,1)).with("frozen", s.frozen.set(1,5432))
      .with("cache", Set(1))}
  action mintChild = all {s.phase == 1,
    s' = s.with("phase", 2).with("registry", s.registry.set(2,2))
      .with("owner", s.owner.set(2,2)).with("frozen", s.frozen.set(2,5433))
      .with("cache", if (s.miss and BUG != "cacheMiss") s.cache else s.cache.union(Set(2)))
      .with("token", 2).with("presented", 2)
      .with("unselected", if (BUG == "eager") 1 else 0)}
  action publicEdit = all {s.phase == 2,
    s' = s.with("phase", 3)
      .with("token", if (Set("fake","borrowed").contains(s.kind)) 3 else 2)
      .with("presented", if (s.kind == "fake") 3 else if (s.kind == "replaced") 1 else 2)
      .with("payload", if (s.kind == "payload") 5440 else s.payload)
      // A user may construct an arbitrary closure, but cannot write registry.
      .with("owner", s.owner.set(3,3)).with("frozen", s.frozen.set(3,5433))}
  val registered = if (BUG == "noRegistry") s.presented else s.registry.get(s.token)
  val authentic = registered != 0 and registered == s.presented and
    s.owner.get(registered) == s.token and
    (BUG == "noPayload" or s.frozen.get(registered) == s.payload)
  val endpoint = authentic and s.route == 0 and s.revision == 0
  action firstCheck = all {s.phase == 3,
    s' = s.with("phase", 4).with("first", endpoint)}
  action callbackEnter = all {s.phase == 4,
    s' = s.with("phase", 5)
      .with("presented", if (s.first and s.kind == "closureRestore") 1 else s.presented)
      .with("route", if (s.first and Set("metadataRestore","metadataStay").contains(s.kind)) 1 else 0)
      .with("revision", if (s.first and s.kind == "revisionABA") 2 else 0)}
  action callbackEffect = all {s.phase == 5,
    s' = s.with("phase", 6).with("effects",
      if (s.first and s.kind == "metadataRestore") s.effects + 1 else s.effects)}
  action callbackRestore = all {s.phase == 6,
    s' = s.with("phase", 7)
      .with("presented", if (s.first and s.kind == "closureRestore") 2 else s.presented)
      .with("route", if (s.first and s.kind == "metadataRestore") 0 else s.route)}
  action finish = {
    val current = if (BUG == "skipFinal") s.first else
      authentic and (s.route == 0 or BUG == "noRoute") and s.revision == 0
    all {s.phase == 7,
      s' = s.with("phase", 8).with("accepted",s.first and current and s.a and (s.b or BUG == "dropB"))
        .with("checkerCalls", if (s.first and authentic and s.route != 0 and BUG == "noRoute") 1 else 0)
        .with("planOwner", if (BUG == "parent") 1 else 2)}
  }
  action terminal = all {s.phase == 8, s' = s}
  action step = any {mintParent, mintChild, publicEdit, firstCheck,
    callbackEnter, callbackEffect, callbackRestore, finish, terminal}
  val AuthenticAtReturn = not(s.accepted) or
    (s.registry.get(s.token) != 0 and s.registry.get(s.token) == s.presented and
     s.owner.get(s.presented) == s.token and s.frozen.get(s.presented) == s.payload)
  val EndpointCurrent = not(s.accepted) or endpoint
  val ParentIsolated = s.phase == 0 or
    (s.registry.get(1) == 1 and s.owner.get(1) == 1 and s.frozen.get(1) == 5432)
  val MissNotCached = s.phase < 2 or not(s.miss) or not(s.cache.contains(2))
  val BothRequirements = not(s.accepted) or (s.a and s.b)
  val ChildPlan = not(s.accepted) or s.planOwner == 2
  val NoForeignKernelCalls = s.checkerCalls == 0
  val LazyBranch = s.unselected == 0
  // Deliberately FALSE: endpoint validity is not a callback-history certificate.
  val NoCallbackEffects = not(s.accepted) or s.effects == 0
  val RejectAll = not(s.accepted)
  val safety = AuthenticAtReturn and EndpointCurrent and ParentIsolated and
    MissNotCached and BothRequirements and ChildPlan and NoForeignKernelCalls and LazyBranch
}
module IssuerProjection { import IssuerProjectionModel(BUG = "none").* }
