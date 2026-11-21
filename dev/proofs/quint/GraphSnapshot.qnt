// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite publication interleavings, not a second SCC/topological value proof.
module GraphSnapshotModel {
  const BUG: str
  type State = {pc: int, head: int, adjacency: int, ranks: int, index: int,
    ticket: int, captured: int, result: int, success: bool,
    oldIndexLive: bool, published: bool, accepted: bool, staleAccepted: bool,
    failedReplacement: bool, retiredAccepted: bool, invalid: Set[int]}
  var s: State
  // Owner 3 is outside the order interval {1,2}, but consumes changed owner 1.
  pure val oldImpact = Set(1,3)
  action init = { s' = {pc: 0, head: 0, adjacency: 0, ranks: 0, index: 0,
    ticket: 0, captured: 0, result: 0, success: false, oldIndexLive: true,
    published: false, accepted: false, staleAccepted: false,
    failedReplacement: false, retiredAccepted: false, invalid: Set()} }
  // The producer captured snapshot 0 before returning from its external work.
  action begin = all { s.pc == 0, s.captured == s.head,
    s' = s.with("pc", 1).with("ticket", 1)
      .with("invalid", if (BUG == "interval") Set(1,2) else oldImpact) }
  action refuseLateStage = all { s.pc == 0, s.captured != s.head,
    s' = s.with("pc", 3) }
  action prepare = {
    nondet success = Set(true,false).oneOf()
    all { s.pc == 1,
      s' = s.with("pc", 2).with("result", s.ticket).with("success", success)
        .with("adjacency", if (BUG == "mixed") 1 else s.adjacency)
        .with("oldIndexLive", if (BUG == "earlyRetire") false else s.oldIndexLive) }
  }
  action extend = all { s.pc == 2, s.ticket == 1,
    s' = s.with("ticket", 2).with("invalid", s.invalid.union(Set(2))) }
  action finishFresh = {
    nondet success = Set(true,false).oneOf()
    all { s.pc == 2, s.ticket == 2, s.result == 1,
      s' = s.with("result", 2).with("success", success) }
  }
  // A competing request can publish before staging or during admission.
  action rival = all { (s.pc == 0 or s.pc == 2), s.head == 0,
    s' = s.with("head", 1).with("adjacency", 1).with("ranks", 1).with("index", 1)
      .with("oldIndexLive", false).with("published", true) }
  action install = {
    val current = s.captured == s.head and s.oldIndexLive
    val exact = s.result == s.ticket
    val allowed = s.success and current and (exact or BUG == "stale")
    val headAfter = if (allowed) 1 else if (BUG == "replaceFailure") 9 else s.head
    all { s.pc == 2,
      s' = s.with("pc", 3).with("head", headAfter)
        .with("adjacency", if (allowed) 1 else s.adjacency)
        .with("ranks", if (allowed) 1 else s.ranks)
        .with("index", if (allowed) 1 else s.index)
        .with("oldIndexLive", if (allowed) false else s.oldIndexLive)
        .with("published", s.published or allowed).with("accepted", allowed)
        .with("staleAccepted", allowed and not(exact))
        .with("failedReplacement", not(allowed) and headAfter != s.head) }
  }
  action oldRequest = all { s.pc == 3, s.published,
    s' = s.with("retiredAccepted", BUG == "retired" or s.oldIndexLive) }
  // Reader can observe a head at any stage; staged tables never become its head.
  action read = { s' = s }
  action step = any {begin, refuseLateStage, prepare, extend, finishFresh, rival, install, oldRequest, read}
  val ConsistentHead = s.head == s.adjacency and s.head == s.ranks and s.head == s.index
  val ExactTicket = not(s.staleAccepted)
  val OldIndexLifetime = s.published or s.oldIndexLive
  val FailedKeepsHead = not(s.failedReplacement)
  val RetiredRefused = not(s.retiredAccepted)
  val FullOldImpact = s.ticket == 0 or oldImpact.subseteq(s.invalid)
  val BoundStage = s.ticket == 0 or s.captured == 0
  val RejectAll = not(s.accepted)
  val safety = ConsistentHead and ExactTicket and OldIndexLifetime and FailedKeepsHead and RetiredRefused and FullOldImpact and BoundStage
}
module GraphSnapshot { import GraphSnapshotModel(BUG = "none").* }
