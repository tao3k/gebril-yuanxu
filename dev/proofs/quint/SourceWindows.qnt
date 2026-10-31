// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SourceWindowsModel {
  const BUG: str
  // Two independent contributors constrain one source; never merge their evidence.
  pure val required = Set(0, 1)
  var phase: int // 0 pure initial check, 1 obligation/effect, 2 fresh return check, 3 terminal
  var index: int
  var source: int
  var bytes: int // -1 absent; 0/1 actual source observation, never a free revision oracle
  var checked: Set[int]
  var requirementsOK: bool
  var conflict: bool
  var accepted: bool
  var windowReads: int
  var totalReads: int
  var obligations: int
  var planOwner: int
  var planPort: int
  var demanded: Set[int]
  pure val childPort = 5433
  pure def expected(contributor: int, incompatible: bool): int =
    if (contributor == 1 and incompatible) 1 else 0
  action init = {
    nondet incompatible = Set(false, true).oneOf()
    all {
      phase' = 0, index' = 0, source' = 0, bytes' = -1,
      checked' = Set(), requirementsOK' = true, conflict' = incompatible,
      accepted' = false, windowReads' = 0, totalReads' = 0,
      obligations' = 0, planOwner' = 0, planPort' = 5432, demanded' = Set()
    }
  }
  action checkNext = {
    val skip = BUG == "omit" and index == 1
    val miss = bytes == -1 or BUG == "repeat"
    val observed = if (miss) source else bytes
    all {
      (phase == 0 or phase == 2), index < 2,
      phase' = phase, index' = index + 1, source' = source,
      bytes' = if (skip) bytes else observed,
      checked' = if (skip) checked else checked.union(Set(index)),
      requirementsOK' = (requirementsOK and (skip or observed == expected(index, conflict))),
      conflict' = conflict, accepted' = false,
      windowReads' = windowReads + (if (miss and not(skip)) 1 else 0),
      totalReads' = totalReads + (if (miss and not(skip)) 1 else 0),
      obligations' = obligations, planOwner' = planOwner, planPort' = planPort,
      demanded' = demanded.union(if (BUG == "eager") Set(0, 1) else Set(0))
    }
  }
  action initialDone = all {
    phase == 0, index == 2, phase' = 1,
    index' = index, source' = source, bytes' = bytes, checked' = checked,
    requirementsOK' = requirementsOK, conflict' = conflict, accepted' = false,
    windowReads' = windowReads, totalReads' = totalReads, obligations' = obligations,
    planOwner' = planOwner, planPort' = planPort, demanded' = demanded
  }
  action effect = all {
    phase == 1, source == 0, source' = 1,
    phase' = phase, index' = index, bytes' = bytes, checked' = checked,
    requirementsOK' = requirementsOK, conflict' = conflict, accepted' = false,
    windowReads' = windowReads, totalReads' = totalReads, obligations' = obligations,
    planOwner' = planOwner, planPort' = planPort, demanded' = demanded
  }
  action returnWindow = all {
    phase == 1, phase' = if (BUG == "skipfinal") 3 else 2,
    index' = if (BUG == "skipfinal") index else 0,
    source' = source, bytes' = if (BUG == "cross") bytes else -1,
    checked' = if (BUG == "skipfinal") checked else Set(), requirementsOK' = true,
    conflict' = conflict, accepted' = (BUG == "skipfinal" and requirementsOK),
    windowReads' = 0, totalReads' = totalReads, obligations' = 1,
    // An old parent value is not a valid child-context plan.
    planOwner' = if (BUG == "receiver") 0 else 1,
    planPort' = if (BUG == "receiver") 5432 else childPort,
    demanded' = demanded
  }
  action finish = all {
    phase == 2, index == 2, phase' = 3,
    accepted' = requirementsOK, index' = index, source' = source, bytes' = bytes,
    checked' = checked, requirementsOK' = requirementsOK, conflict' = conflict,
    windowReads' = windowReads, totalReads' = totalReads, obligations' = obligations,
    planOwner' = planOwner, planPort' = planPort, demanded' = demanded
  }
  action terminal = all {
    phase == 3, phase' = phase, index' = index, source' = source, bytes' = bytes,
    checked' = checked, requirementsOK' = requirementsOK, conflict' = conflict,
    accepted' = accepted, windowReads' = windowReads, totalReads' = totalReads,
    obligations' = obligations, planOwner' = planOwner, planPort' = planPort, demanded' = demanded
  }
  action step = any { checkNext, initialDone, effect, returnWindow, finish, terminal }
  val CurrentEvidence = not(accepted) or required.forall(r => source == expected(r, conflict))
  val CompleteRequirements = not(accepted) or checked == required
  val FinalReceiver = not(accepted) or (planOwner == 1 and planPort == childPort)
  val OncePerWindow = windowReads <= 1
  val FreshReturnRead = phase != 3 or totalReads == 2
  val ChildObligations = not(accepted) or obligations == 1
  val LazyBranch = demanded.subseteq(Set(0))
  // Expected counterexample: ensure that successful admission is reachable.
  val RejectAll = not(accepted)
  val safety = CurrentEvidence and CompleteRequirements and FinalReceiver and
    OncePerWindow and FreshReturnRead and ChildObligations and LazyBranch
}
module SourceWindows {
  import SourceWindowsModel(BUG = "none").*
}
