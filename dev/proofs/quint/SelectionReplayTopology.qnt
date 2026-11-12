// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite replay certificate boundary, not a production cache implementation.
module SelectionReplayTopologyModel {
  const BUG: str
  var s: {done: bool, safe: bool, order: bool, delivered: bool,
    parent: int, unused: int, both: bool, buildClosed: bool}
  action init = s' = {done: false, safe: true, order: true, delivered: true,
    parent: 5432, unused: 0, both: true, buildClosed: true}
  action verify = {
    nondet changedEdge = Set(false, true).oneOf()
    nondet reversedRoots = Set(false, true).oneOf()
    nondet forged = Set(false, true).oneOf()
    nondet stale = Set(false, true).oneOf()
    nondet revisedReceiver = Set(false, true).oneOf()
    nondet cachedOwner = Set(false, true).oneOf()
    nondet weakEviction = Set(false, true).oneOf()
    nondet constructorTrusted = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    // Issuance authenticates the dependency sequence, even on a topology hit.
    val authentic = not(forged) and not(changedEdge)
    val fresh = not(stale) and not(revisedReceiver)
    val hit = cachedOwner and not(weakEviction) and (not(reversedRoots) or BUG == "roots")
    val accepts = (hit and BUG == "verdict" or authentic and fresh) and a and b
    // Root order mismatch rebuilds; never canonicalize roots as an unordered set.
    val usesSavedOrder = hit
    all {not(s.done), s' = {done: true,
      safe: not(accepts) or authentic and fresh,
      order: not(reversedRoots and usesSavedOrder),
      delivered: BUG != "seen", parent: s.parent, unused: s.unused,
      both: not(accepts) or a and b,
      buildClosed: hit or constructorTrusted or BUG != "constructor"}}
  }
  action terminal = all {s.done, s' = s}
  action step = any {verify, terminal}
  val Fresh = s.safe
  val Order = s.order
  val Delivery = s.delivered
  val Construction = s.buildClosed
  val safety = Fresh and Order and Delivery and Construction and s.both and s.parent == 5432 and s.unused == 0
}
module SelectionReplayTopology { import SelectionReplayTopologyModel(BUG = "none").* }
