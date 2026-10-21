// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CompilerEnrollmentModel {
  const BUG: str
  // Two demanded SDK contexts share a source. Topology enrollment is NOT a
  // successful admission: source can change between two demands of one root.
  pure def closure(root: int): Set[int] = Set(root, 2)
  var enrolled: Set[int]
  var sources: Set[int]
  var dirty: Set[int]
  var staleAccepted: bool
  var accepted: bool
  var steps: int
  action init = all {enrolled' = Set(), sources' = Set(), dirty' = Set(),
    staleAccepted' = false, accepted' = false, steps' = 0}
  action demand = {
    nondet root = Set(0, 1).oneOf()
    val hit = enrolled.contains(root)
    val fresh = dirty.intersect(closure(root)) == Set()
    val allowed = fresh or (BUG == "reuseApproval" and hit)
    all {steps < 5,
      enrolled' = enrolled.union(Set(root)),
      sources' = if (hit or BUG == "dropEnrollment") sources else sources.union(closure(root)),
      dirty' = dirty, steps' = steps + 1,
      staleAccepted' = (staleAccepted or (allowed and not(fresh))),
      accepted' = (accepted or allowed)}
  }
  action change = {
    nondet source = Set(0, 1, 2).oneOf()
    all {steps < 5, dirty' = dirty.union(Set(source)), steps' = steps + 1,
      enrolled' = enrolled, sources' = sources,
      staleAccepted' = staleAccepted, accepted' = accepted}
  }
  action terminal = all {steps >= 5, enrolled' = enrolled, sources' = sources,
    dirty' = dirty, steps' = steps, staleAccepted' = staleAccepted, accepted' = accepted}
  action step = any {demand, change, terminal}
  val Complete = enrolled.forall(root => closure(root).subseteq(sources))
  val FreshDemand = not(staleAccepted)
  val RejectAll = not(accepted)
  val safety = Complete and FreshDemand
}
module CompilerEnrollment {
  import CompilerEnrollmentModel(BUG = "none").*
}
