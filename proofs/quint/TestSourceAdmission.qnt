// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module TestSourceAdmissionModel {
  const BUG: str
  // One source graph: owners 0 and 2, private dependencies 1 and 3.
  pure val nodes = Set(0, 1, 2, 3)
  pure val selected = Set(0, 2)
  pure def dependencies(node: int): Set[int] =
    if (node == 0) Set(1) else if (node == 2) Set(3) else Set()
  var phase: int // 0 idle, 1 discovery, 2 ready, 3 executing, 4 finished
  var pending: Set[int]
  var seen: Set[int]
  var versions: int -> int
  var captured: int -> int
  var graphForced: bool
  var graphIdentity: int
  var accepted: bool
  var fixtureHeld: bool
  var policyValid: bool
  val fresh = seen.forall(n => captured.get(n) == versions.get(n))
  val canRun = fresh and (not(graphForced) or policyValid)
  action init = all {
    phase' = 0, pending' = Set(), seen' = Set(),
    versions' = nodes.mapBy(_ => 0), captured' = nodes.mapBy(_ => -1),
    graphForced' = false, graphIdentity' = 7, accepted' = false,
    fixtureHeld' = false, policyValid' = true
  }
  action request = all {
    phase == 0, phase' = 1,
    pending' = if (BUG == "eager") selected else Set(0), seen' = seen,
    versions' = versions, captured' = captured, graphForced' = graphForced,
    graphIdentity' = graphIdentity, accepted' = false,
    fixtureHeld' = false, policyValid' = policyValid
  }
  action readNext = {
    nondet node = pending.oneOf()
    all {
      phase == 1, pending.size() > 0, phase' = 1,
      seen' = seen.union(Set(node)),
      pending' = pending.exclude(Set(node)).union(dependencies(node).exclude(seen.union(Set(node)))),
      captured' = if (seen.contains(node)) captured else captured.set(node, versions.get(node)),
      versions' = versions, graphForced' = graphForced, graphIdentity' = graphIdentity,
      accepted' = accepted, fixtureHeld' = fixtureHeld, policyValid' = policyValid
    }
  }
  action ready = all {
    phase == 1, pending == Set(), phase' = 2, pending' = pending, seen' = seen,
    versions' = versions, captured' = captured, graphForced' = graphForced,
    graphIdentity' = graphIdentity, accepted' = false,
    fixtureHeld' = fixtureHeld, policyValid' = policyValid
  }
  action changeSource = {
    nondet node = nodes.oneOf()
    all {
      phase >= 1, phase <= 3, versions.get(node) == 0,
      versions' = versions.set(node, 1), phase' = phase, pending' = pending,
      seen' = seen, captured' = captured, graphForced' = graphForced,
      graphIdentity' = graphIdentity, accepted' = accepted,
      fixtureHeld' = fixtureHeld, policyValid' = policyValid
    }
  }
  action beginRun = all {
    phase == 2, phase' = if (canRun) 3 else 4, fixtureHeld' = canRun,
    pending' = pending, seen' = seen, versions' = versions, captured' = captured,
    graphForced' = graphForced, graphIdentity' = graphIdentity,
    accepted' = false, policyValid' = policyValid
  }
  action finishRun = {
    nondet success = Set(false, true).oneOf()
    all {
      phase == 3, phase' = 4,
      accepted' = (success and (BUG == "stale" or fresh) and (not(graphForced) or policyValid)),
      fixtureHeld' = BUG == "cleanup", pending' = pending, seen' = seen,
      versions' = versions, captured' = captured, graphForced' = graphForced,
      graphIdentity' = graphIdentity, policyValid' = policyValid
    }
  }
  // Extend the same demand/cache after an explicit full-Graph request.
  action demandGraph = all {
    phase == 4, not(graphForced), not(fixtureHeld), phase' = 1,
    graphForced' = true, pending' = selected.exclude(seen), seen' = seen,
    graphIdentity' = if (BUG == "secondGraph") 99 else graphIdentity,
    versions' = versions, captured' = captured, accepted' = false,
    fixtureHeld' = false, policyValid' = policyValid
  }
  action rejectPolicy = all {
    graphForced, phase >= 1, phase <= 3, policyValid,
    policyValid' = false, phase' = phase, pending' = pending, seen' = seen,
    versions' = versions, captured' = captured, graphForced' = graphForced,
    graphIdentity' = graphIdentity, accepted' = accepted, fixtureHeld' = fixtureHeld
  }
  action terminal = all {
    phase == 4, phase' = phase, pending' = pending, seen' = seen,
    versions' = versions, captured' = captured, graphForced' = graphForced,
    graphIdentity' = graphIdentity, accepted' = accepted,
    fixtureHeld' = fixtureHeld, policyValid' = policyValid
  }
  action step = any { request, readNext, ready, changeSource, beginRun, finishRun, demandGraph, rejectPolicy, terminal }
  val NoUnrelatedExpansion = graphForced or seen.subseteq(Set(0, 1))
  val SameGraphIdentity = graphIdentity == 7
  val CurrentEvidence = not(accepted) or fresh
  val FailureCleanup = phase != 4 or not(fixtureHeld)
  val CompleteConfiguration = not(accepted and graphForced) or (seen == nodes and policyValid)
  val safety = NoUnrelatedExpansion and SameGraphIdentity and CurrentEvidence and FailureCleanup and CompleteConfiguration
}
module TestSourceAdmission {
  import TestSourceAdmissionModel(BUG = "none").*
}
