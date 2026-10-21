// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Window transitions model actual possible writes, not a trusted epoch counter.
// PURE_REPLAY restricts replay to a closed read-only producer. It does NOT say
// every callback supplied through the public MOP constructor is effect-free.
module ReturnWindowsModel {
  const BUG: str
  const PURE_REPLAY: bool
  type Request = {id: int, path: int, expected: int}
  type Checked = {ok: bool, bytes: int -> int, reads: int, seen: Set[int]}
  pure val paths = Set(0, 1, 2)
  pure val empty = paths.mapBy(_ => -1)
  pure val base = List({id: 0, path: 0, expected: 0}, {id: 1, path: 0, expected: 0})
  pure val late = {id: 2, path: 1, expected: 0}
  pure def check(world: int -> int, bytes: int -> int, requests: List[Request]): Checked =
    requests.foldl({ok: true, bytes: bytes, reads: 0, seen: Set()}, (out, request) => {
      val missing = out.bytes.get(request.path) == -1
      val actual = if (missing) world.get(request.path) else out.bytes.get(request.path)
      {ok: out.ok and actual == request.expected,
       bytes: out.bytes.set(request.path, actual),
       reads: out.reads + (if (missing) 1 else 0), seen: out.seen.union(Set(request.id))}
    })
  type State = {phase: int, world: int -> int, bytes: int -> int,
    conflict: bool, parties: Set[int], partyOK: bool, accepted: bool,
    callbackStarted: bool, callbackSource: int, tailReads: int,
    tailSeen: Set[int], demanded: Set[int]}
  var s: State
  action init = {
    nondet incompatible = Set(false, true).oneOf()
    all { s' = {phase: 0, world: paths.mapBy(_ => 0), bytes: empty,
      conflict: incompatible, parties: Set(), partyOK: true, accepted: false,
      callbackStarted: false, callbackSource: -1, tailReads: 0,
      tailSeen: Set(), demanded: Set()} }
  }
  action beforeChange = {
    nondet path = Set(0, 1).oneOf()
    all { s.phase == 0, s.world.get(path) == 0,
      s' = s.with("world", s.world.set(path, 1)) }
  }
  action beforeCallback = {
    val result = check(s.world, empty, base)
    all { s.phase == 0,
      s' = s.with("phase", if (result.ok or BUG == "skipBefore") 1 else 9)
            .with("bytes", result.bytes).with("demanded", Set(0)) }
  }
  action contribution = {
    // Two independent requirements are checked before any prototype override.
    val requests = List({id: 0, port: 5433},
                        {id: 1, port: if (s.conflict) 5440 else 5433})
    val selected = if (BUG == "dropParty") requests.slice(0, 1) else requests
    all { s.phase == 1,
      s' = s.with("phase", 2).with("callbackStarted", true)
            .with("callbackSource", s.world.get(0))
            .with("parties", selected.foldl(Set(), (out, row) => out.union(Set(row.id))))
            .with("partyOK", selected.foldl(true, (out, row) => out and row.port == 5433)) }
  }
  action contributionEffect = all {
    s.phase == 2, s.world.get(0) == 0,
    s' = s.with("world", s.world.set(0, 1))
  }
  action afterContribution = {
    val result = check(s.world, if (BUG == "crossContribution") s.bytes else empty, base)
    all { s.phase == 2,
      s' = s.with("phase", if (result.ok) 3 else 9).with("bytes", result.bytes) }
  }
  action diagnosticCallback = {
    nondet change = Set(false, true).oneOf()
    all { s.phase == 3,
      s' = s.with("phase", 4).with("world", if (change) s.world.set(0, 1) else s.world) }
  }
  action returnCallbackCheck = {
    val result = check(s.world, empty, base)
    all { s.phase == 4,
      s' = s.with("phase", if (result.ok) 5 else 9).with("bytes", result.bytes) }
  }
  action returnCallbackEffect = {
    nondet change = Set(false, true).oneOf()
    all { s.phase == 5,
      s' = s.with("phase", 6).with("world", if (change) s.world.set(0, 1) else s.world) }
  }
  action exitSourceCheck = {
    val result = check(s.world, if (BUG == "trustReturn") s.bytes else empty, base)
    all { s.phase == 6,
      s' = s.with("phase", if (result.ok) 7 else 9).with("bytes", result.bytes)
            .with("tailReads", result.reads) }
  }
  action replay = {
    // Native closed replay discovers a selected dependency without evaluating
    // getters. Open current? callbacks may write AFTER exitSourceCheck.
    nondet target = (if (PURE_REPLAY) Set(-1) else Set(-1, 0, 1)).oneOf()
    all { s.phase == 7,
      s' = s.with("phase", 8)
            .with("world", if (target == -1) s.world else s.world.set(target, 1))
            .with("demanded", s.demanded.union(Set(1))) }
  }
  action finalCheck = {
    val requests = if (BUG == "omitLate") base else base.append(late)
    val reuse = BUG == "trustReturn" or BUG == "crossReplay" or (PURE_REPLAY and BUG != "repeat")
    val result = check(s.world, if (reuse) s.bytes else empty, requests)
    all { s.phase == 8,
      s' = s.with("phase", 9).with("accepted", s.partyOK and result.ok)
            .with("tailReads", s.tailReads + result.reads).with("tailSeen", result.seen) }
  }
  action terminal = all { s.phase == 9, s' = s }
  action step = any { beforeChange, beforeCallback, contribution, contributionEffect,
    afterContribution, diagnosticCallback, returnCallbackCheck, returnCallbackEffect,
    exitSourceCheck, replay, finalCheck, terminal }
  val CallbackEntry = not(s.callbackStarted) or s.callbackSource == 0
  val PostContribution = s.phase != 3 or s.world.get(0) == 0
  val FinalSources = not(s.accepted) or (s.world.get(0) == 0 and s.world.get(1) == 0)
  val CompleteProjection = not(s.accepted) or s.tailSeen == Set(0, 1, 2)
  val TwoRequirements = not(s.accepted) or (s.parties == Set(0, 1) and not(s.conflict))
  val PureBudget = not(s.accepted) or s.tailReads == (if (PURE_REPLAY) 2 else 3)
  val LazyBranch = s.demanded.subseteq(Set(0, 1))
  val RejectAll = not(s.accepted)
  val safety = CallbackEntry and PostContribution and FinalSources and
    CompleteProjection and TwoRequirements and PureBudget and LazyBranch
}
module ReturnWindows {
  import ReturnWindowsModel(BUG = "none", PURE_REPLAY = false).*
}
