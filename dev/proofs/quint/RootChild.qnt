// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Proposed protocol: selected child analysis has NO publication authority.
// Final sources are checked only after callbacks; pure windows are stable.
module RootChildModel {
  const BUG: str
  var phase: int
  var index: int
  var source0: int
  var source1: int
  var bytes0: int
  var bytes1: int
  var ok: bool
  var conflict: bool
  var client: int
  var accepted: bool
  var checked: Set[int]
  var obligations: int
  var owner: int
  var planPort: int
  var reads: int
  var demanded: Set[int]

  action init = {
    nondet incompatible = Set(false, true).oneOf()
    nondet clientPort = Set(5432, 5433).oneOf()
    all {
      phase' = 0,
      index' = 0,
      source0' = 0,
      source1' = 0,
      bytes0' = -1,
      bytes1' = -1,
      ok' = true,
      conflict' = incompatible,
      client' = clientPort,
      accepted' = false,
      checked' = Set(),
      obligations' = 0,
      owner' = 0,
      planPort' = 5432,
      reads' = 0,
      demanded' = Set()
    }
  }
  action firstChild = all {
    phase == 0,
    phase' = (1),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (client == 5433),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (Set(0)),
    obligations' = (1),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (if (BUG == "eager") Set(0, 1, 2) else Set(0))
  }
  action betweenChildren = all {
    phase == 1,
    phase' = (2),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action secondChild = all {
    phase == 2,
    phase' = (3),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok and (BUG == "omit" or not(conflict))),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (if (BUG == "omit") checked else checked.union(Set(1))),
    obligations' = (if (BUG == "skipchild") obligations else obligations + 1),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded.union(Set(1)))
  }
  action effect0 = all {
    (phase == 1 or phase == 3),
    source0 == 0,
    phase' = (phase),
    index' = (index),
    source0' = (1),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action effect1 = all {
    (phase == 1 or phase == 3),
    source1 == 0,
    phase' = (phase),
    index' = (index),
    source0' = (source0),
    source1' = (1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action beginFinal = all {
    phase == 3,
    phase' = (if (BUG == "analyticAuthority") 6 else 4),
    index' = (0),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (if (BUG == "crossEffect") 0 else -1),
    bytes1' = (if (BUG == "crossEffect") 0 else -1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (BUG == "analyticAuthority" and ok),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (if (BUG == "parent") 0 else 1),
    planPort' = (if (BUG == "parent") 5432 else 5433),
    reads' = (reads),
    demanded' = (demanded)
  }
  action readShared = all {
    phase == 4,
    index < 2,
    phase' = (phase),
    index' = (index + 1),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (if (bytes0 == -1) source0 else bytes0),
    bytes1' = (bytes1),
    ok' = (ok and (if (bytes0 == -1) source0 else bytes0) == 0),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads + (if (bytes0 == -1) 1 else 0)),
    demanded' = (demanded)
  }
  action readPrivate = all {
    phase == 4,
    index == 2,
    phase' = (5),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (if (bytes1 == -1) source1 else bytes1),
    ok' = (ok and (BUG == "omitSource" or (if (bytes1 == -1) source1 else bytes1) == 0)),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads + (if (bytes1 == -1) 1 else 0)),
    demanded' = (demanded)
  }
  action lateEffect = all {
    BUG == "lateEffect",
    phase == 5,
    source0 == 0,
    phase' = (phase),
    index' = (index),
    source0' = (1),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action finish = all {
    phase == 5,
    phase' = (6),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (ok),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action terminal = all {
    phase == 6,
    phase' = (phase),
    index' = (index),
    source0' = (source0),
    source1' = (source1),
    bytes0' = (bytes0),
    bytes1' = (bytes1),
    ok' = (ok),
    conflict' = (conflict),
    client' = (client),
    accepted' = (accepted),
    checked' = (checked),
    obligations' = (obligations),
    owner' = (owner),
    planPort' = (planPort),
    reads' = (reads),
    demanded' = (demanded)
  }
  action step = any { firstChild, betweenChildren, secondChild, effect0, effect1, beginFinal, readShared, readPrivate, lateEffect, finish, terminal }
  val FinalSources = not(accepted) or (source0 == 0 and source1 == 0)
  val TwoRequirements = not(accepted) or (checked == Set(0, 1) and not(conflict))
  val DomainChecks = not(accepted) or (obligations == 2 and client == 5433)
  val ReceiverIsolation = not(accepted) or (owner == 1 and planPort == 5433)
  val FinalReadBudget = not(accepted) or reads == 2
  val LazyBranch = demanded.subseteq(Set(0, 1))
  val RejectAll = not(accepted)
  val safety = FinalSources and TwoRequirements and DomainChecks and
    ReceiverIsolation and FinalReadBudget and LazyBranch
}
module RootChild {
  import RootChildModel(BUG = "none").*
}
