// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite frozen read-record graph; IDs are identities, not slot/payload names.
module IdentityDFSModel {
  const BUG: str
  pure val nodes = Set(0, 1, 2, 3, 4)
  pure val reached = Set(0, 1, 2, 3)
  pure def edges(id: int): List[int] =
    if (id == 0) List(1, 2) else if (id == 1 or id == 2) List(3)
    else if (id == 3) List(1) else List()
  type State = {phase: int, pending: List[int], seen: Set[int], order: List[int],
    visits: int -> int, rev: int -> int, finalPending: Set[int], finalSeen: Set[int],
    ticks: int, source: int, conflict: bool, planOwner: int, accepted: bool}
  var s: State
  action init = {
    nondet conflict = Set(false, true).oneOf()
    all { s' = {phase: 0, pending: List(0, 0), seen: Set(), order: List(),
      visits: nodes.mapBy(_ => 0), rev: nodes.mapBy(_ => 0),
      finalPending: Set(), finalSeen: Set(), ticks: 0, source: 0,
      conflict: conflict, planOwner: if (BUG == "parent") 1 else 2, accepted: false} }
  }
  action visit = {
    nondet effect = Set(0, 1, 2, 3).oneOf()
    all { s.phase == 0, s.pending.length() > 0, s.ticks < 8,
      val id = s.pending.nth(0)
      val rest = s.pending.slice(1, s.pending.length())
      // Distinct records 1 and 2 may have equal payloads. Comparing payloads is wrong.
      val key = if (BUG == "payload" and id == 2) 1 else id
      s' = if (s.seen.contains(key))
        s.with("pending", rest).with("ticks", s.ticks + 1)
      else if (s.rev.get(id) != 0) s.with("phase", 2)
      else s.with("pending", edges(id).concat(rest))
            .with("seen", if (BUG == "lateMark") s.seen else s.seen.union(Set(key)))
            .with("order", s.order.append(id))
            .with("visits", s.visits.set(id, s.visits.get(id) + 1))
            .with("ticks", s.ticks + 1)
            // 1: cold metadata hook; 2: source observer; 3: invalidate an earlier record.
            .with("source", if (effect == 1 or effect == 2) 1 else s.source)
            .with("rev", if (effect == 3) s.rev.set(0, 1) else s.rev) }
  }
  action beginFinal = all {
    s.phase == 0, s.pending.length() == 0,
    s' = s.with("phase", 1)
          .with("finalPending", if (BUG == "noFinal") Set()
             else if (BUG == "dropFinal") s.seen.exclude(Set(3)) else s.seen)
  }
  action recheck = {
    nondet id = s.finalPending.union(Set(-1)).oneOf()
    nondet change = (if (BUG == "finalWrite") s.finalSeen.union(Set(-1)) else Set(-1)).oneOf()
    all { s.phase == 1, id != -1,
      s' = if (s.rev.get(id) != 0) s.with("phase", 2)
      else s.with("finalPending", s.finalPending.exclude(Set(id)))
            .with("finalSeen", s.finalSeen.union(Set(id)))
            // Open current? may validate itself, then invalidate an earlier check.
            .with("rev", if (change == -1) s.rev else s.rev.set(change, 1)) }
  }
  action finish = {
    val sourceOK = BUG == "sourceReuse" or s.source == 0
    val requirementsOK = not(s.conflict) or not(s.seen.contains(2))
    val ownerOK = BUG == "parent" or s.planOwner == 2
    all { s.phase == 1, s.finalPending == Set(),
      s' = s.with("phase", 2).with("accepted", sourceOK and requirementsOK and ownerOK) }
  }
  // Finite counterexample horizon only. The positive program never reaches it;
  // Lean proves termination for arbitrary finite closed graphs without this cap.
  action overflow = all { s.phase == 0, s.ticks == 8, s' = s.with("phase", 2) }
  action terminal = all { s.phase == 2, s' = s }
  action step = any { visit, beginFinal, recheck, finish, overflow, terminal }
  val UniqueVisit = nodes.forall(id => s.visits.get(id) <= 1)
  val TerminationBound = s.ticks <= 7
  val CompleteCoverage = not(s.accepted) or s.seen == reached
  val FinalCoverage = not(s.accepted) or s.finalSeen == s.seen
  val RecheckedCurrent = not(s.accepted) or s.seen.forall(id => s.rev.get(id) == 0)
  val SourcesCurrent = not(s.accepted) or s.source == 0
  val TwoRequirements = not(s.accepted) or
    (s.seen.contains(1) and s.seen.contains(2) and not(s.conflict))
  val ReceiverIdentity = not(s.accepted) or s.planOwner == 2
  val LazyBranch = not(s.seen.contains(4)) and s.visits.get(4) == 0
  val RejectAll = not(s.accepted)
  val safety = UniqueVisit and TerminationBound and CompleteCoverage and FinalCoverage and
    RecheckedCurrent and SourcesCurrent and TwoRequirements and ReceiverIdentity and LazyBranch
}
module IdentityDFS {
  import IdentityDFSModel(BUG = "none").*
}
