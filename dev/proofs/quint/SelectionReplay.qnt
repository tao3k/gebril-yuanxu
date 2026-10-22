// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SelectionReplayModel {
  const BUG: str
  // Serial native checker + revision policy contain no opaque callbacks.
  // A source observer is an open boundary and retains the original keepTail.
  var s: {done: bool, sameDiagnostic: bool, staleAccepted: bool,
    observerTail: bool, parent: int, unused: int, accepted: bool, costBound: bool, lookupCorrect: bool}
  action init = s' = {done: false, sameDiagnostic: true, staleAccepted: false,
    observerTail: true, parent: 5432, unused: 0, accepted: false, costBound: true, lookupCorrect: true}
  action verify = {
    nondet prep = Set(false, true).oneOf()
    nondet admit = Set(false, true).oneOf()
    nondet policy = Set(false, true).oneOf()
    nondet observer = Set(false, true).oneOf()
    nondet changes = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    // Independent collector placement; not a native GC prediction.
    nondet collection = Set(0, 45).oneOf()
    // 0 absent, 1 cached false, 2 cached true. Cache state is fixed within
    // one existing pure window; a miss invokes the original query once.
    nondet cached = Set(0, 1, 2).oneOf()
    nondet fetched = Set(1, 2).oneOf()
    val miss = cached == 0 or (BUG == "falseMiss" and cached == 1)
    val chosen = if (miss) fetched else cached
    val expected = if (cached == 0) fetched else cached
    val after = prep and not(observer and changes)
    val prefix = if (not(prep)) 1 else if (not(admit)) 2 else if (not(policy)) 3 else 0
    val ordered = if (BUG == "reorder" and not(admit)) 2 else prefix
    val reference = if (prefix != 0) prefix else if (not(after)) 1 else 0
    val keepTail = observer and BUG != "skipObserver"
    val actual = if (ordered != 0) ordered else if (keepTail and not(after)) 1 else 0
    all {not(s.done), s' = {done: true, sameDiagnostic: actual == reference,
      staleAccepted: actual == 0 and not(after),
      observerTail: not(observer) or keepTail, parent: s.parent, unused: s.unused,
      accepted: actual == 0 and a and b, costBound: 6 + 8 + collection <= 9 + 8,
      lookupCorrect: chosen == expected and (cached == 0 or not(miss))}}
  }
  action terminal = all {s.done, s' = s}
  action step = any {verify, terminal}
  val Diagnostic = s.sameDiagnostic
  val Current = not(s.staleAccepted)
  val Observer = s.observerTail
  val Isolated = s.parent == 5432 and s.unused == 0
  val RejectAll = not(s.accepted)
  val FewerMeansFaster = s.costBound
  val FalseHit = s.lookupCorrect
  val safety = Diagnostic and Current and Observer and Isolated and FalseHit
}
module SelectionReplay { import SelectionReplayModel(BUG = "none").* }
