// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CarrierRootsModel {
  const BUG: str
  // Native reader/binding roots (9 -> 0), effective method (1), invocation
  // frame (2), arguments (3), shared method (4), private continuation payload
  // (5), read roots (6), and
  // constructor-wide initializer environments (7..8). Not a byte/GC model.
  pure val nodes = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
  pure val payloads = Set(3, 4, 5)
  pure def edges(n: int, constants: bool): Set[int] =
    if (n == 9) { if (BUG == "clearSDK") Set() else Set(0) }
    else if (n == 0) Set(4)
    else if (n == 6) Set(1, 2)
    else if (n == 1) {
      if (constants) { if (BUG == "dropArgument") Set(4) else Set(3, 4) }
      else Set(7)
    } else if (n == 2) {
      if (constants) { if (BUG == "dropArgument") Set(1, 4, 5) else Set(1, 3, 4, 5) }
      else Set(8)
    } else if (n == 7) Set(3, 4)
    else if (n == 8) Set(1, 3, 4, 5) else Set()
  pure def reachable(roots: Set[int], constants: bool): Set[int] =
    nodes.fold(roots, (region, _) =>
      region.union(region.fold(Set(), (out, n) => out.union(edges(n, constants)))))
  type State = {phase: int, stack: Set[int], reads: Set[int], diagnostic: Set[int]}
  var s: State
  action init = {
    s' = {phase: 0, stack: Set(1, 2), reads: Set(), diagnostic: Set()}
  }
  action returnFromMethod = all {
    s.phase == 0,
    s' = {phase: 1, stack: Set(),
      reads: if (BUG == "forgetRead") Set() else Set(6),
      diagnostic: if (BUG == "strongObserver") Set(2) else Set()}
  }
  action releaseGraph = all {
    s.phase == 1, s' = s.with("phase", 2).with("reads", Set())
  }
  action terminal = all { s.phase == 2, s' = s }
  action step = any { returnFromMethod, releaseGraph, terminal }
  val roots = Set(9).union(s.stack).union(s.reads).union(s.diagnostic)
  // The lifecycle gate starts at the completed-call boundary. Constructor
  // validation itself is exercised by the native positive/negative controls.
  val SamePayloads = s.phase == 0 or reachable(roots, true).intersect(payloads) ==
    reachable(roots, false).intersect(payloads)
  val NoInitializerEnvironments = reachable(roots, true).intersect(Set(7, 8)) == Set()
  val ReadRetention = s.phase != 1 or Set(1, 2, 3, 4, 5).subseteq(reachable(roots, true))
  // The shared method remains owned by the canonical runtime. Only private
  // call carriers/payloads may disappear; do not model clearing SDK bindings.
  val CanonicalPreserved = s.phase == 0 or reachable(roots, true).contains(4)
  val WeakDiagnostic = s.phase != 2 or
    reachable(roots, true).intersect(Set(1, 2, 3, 5)) == Set()
  val PayloadGoneAfterReturn = s.phase != 1 or reachable(roots, true).intersect(Set(3, 5)) == Set()
  val RejectAll = s.phase != 2
  val safety = SamePayloads and NoInitializerEnvironments and ReadRetention and WeakDiagnostic and CanonicalPreserved
}
module CarrierRoots { import CarrierRootsModel(BUG = "none").* }
