// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module OwnedReadsModel {
  const BUG: str
  // External policy, Contract, source, Generic and transitive parent policy;
  // the last covers both carrier prototypes and native validation ancestors.
  // 5 and 6 are Core-created call/receipt identities. 7 is unchanged.
  pure val external = Set(0, 1, 2, 3, 4)
  pure val owned = Set(5, 6)
  pure val trace = external.union(owned)
  // A shared/cyclic owned region exposes the Contract only BELOW node 6.
  // Stop at external tokens; their original native replay owns their suffix.
  pure def deps(n: int): Set[int] =
    if (n == 5) Set(0, 2, 3, 4, 6)
    else if (n == 6) Set(1, 5) else Set()
  pure val walked = trace.fold(Set(5), (seen, _) =>
    seen.union(seen.fold(Set(), (successors, n) =>
      if (owned.contains(n)) successors.union(deps(n)) else successors)))
  pure val frontier = walked.exclude(owned)
  var phase: int
  var closed: bool
  var escaped: bool
  var alive: bool
  var token: bool
  var changed: Set[int]
  var accepted: bool
  var constructed: bool
  var editedDuring: bool
  var parentEditedDuring: bool
  val captured = if (BUG == "promotion") frontier.exclude(Set(1))
                 else if (BUG == "policy") frontier.exclude(Set(4)) else frontier
  action init = all {
    phase' = 0, closed' = false, escaped' = false, alive' = true,
    token' = true, changed' = Set(), accepted' = false,
    constructed' = false, editedDuring' = false, parentEditedDuring' = false
  }
  action finish = all {
    phase == 0,
    nondet known = Set(false, true).oneOf()
    nondet escape = Set(false, true).oneOf()
    nondet own = Set(false, true).oneOf()
    nondet edited = Set(false, true).oneOf()
    nondet parentEdited = Set(false, true).oneOf()
    all { phase' = 1,
      closed' = (known and (own or BUG == "construction")
        and (not(edited) or BUG == "generation")
        and (not(parentEdited) or BUG == "parentDuring")),
      parentEditedDuring' = parentEdited,
      constructed' = own, editedDuring' = edited, escaped' = escape,
      alive' = alive, token' = token, changed' = changed, accepted' = accepted }
  }
  action mutate = all {
    phase == 1,
    nondet identity = trace.union(Set(7)).oneOf()
    all { phase' = 2, changed' = Set(identity), closed' = closed,
      escaped' = escaped, alive' = alive, token' = token, accepted' = accepted,
      constructed' = constructed, editedDuring' = editedDuring, parentEditedDuring' = parentEditedDuring }
  }
  action collect = all {
    phase == 2, phase' = 3,
    alive' = (escaped or (not(closed) and BUG != "open")),
    // A live, invalidated receiver can have lost its original read table.
    token' = (changed.intersect(owned) == Set()),
    changed' = changed, closed' = closed, escaped' = escaped, accepted' = accepted,
    constructed' = constructed, editedDuring' = editedDuring, parentEditedDuring' = parentEditedDuring
  }
  val weakCurrent = not(alive) or
    ((token or BUG == "missing") and (BUG == "missing" or changed.intersect(owned) == Set()))
  val projectedCurrent = captured.intersect(changed) == Set() and weakCurrent
  action publish = all {
    phase == 3, phase' = 4,
    accepted' = (if (not(closed)) trace.intersect(changed) == Set()
      else if (BUG == "dead" and not(alive)) true else projectedCurrent),
    changed' = changed, closed' = closed, escaped' = escaped,
    alive' = alive, token' = token, constructed' = constructed, editedDuring' = editedDuring,
    parentEditedDuring' = parentEditedDuring
  }
  action terminal = all {
    phase == 4, phase' = phase, accepted' = accepted, changed' = changed,
    closed' = closed, escaped' = escaped, alive' = alive, token' = token,
    constructed' = constructed, editedDuring' = editedDuring, parentEditedDuring' = parentEditedDuring
  }
  action step = any { finish, mutate, collect, publish, terminal }
  val Complete = external.subseteq(captured)
  val Current = not(accepted) or
    (external.intersect(changed) == Set() and
      (not(alive) or owned.intersect(changed) == Set()))
  val UnknownStrong = phase < 3 or closed or alive
  val MissingRefused = phase != 4 or not(alive) or token or not(accepted)
  val RejectAll = phase != 4
  val ConstructorOnly = phase == 0 or not(closed) or constructed
  val GenerationStable = phase == 0 or not(closed) or (not(editedDuring) and not(parentEditedDuring))
  val safety = Complete and Current and UnknownStrong and MissingRefused and ConstructorOnly and GenerationStable
}
module OwnedReads { import OwnedReadsModel(BUG = "none").* }
