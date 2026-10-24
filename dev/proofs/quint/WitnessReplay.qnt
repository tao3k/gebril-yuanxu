// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// One closed live-witness replay; native DFS and its final pass are premises.
module WitnessReplayModel {
  const BUG: str
  pure val owned = Set(0, 1)
  pure val shared = Set(2, 3)
  pure val complete = owned.union(shared)
  type State = {phase: int, closed: bool, live: Set[int], token: bool,
    required: Set[int], covered: Set[int], dirty: Set[int],
    firstValid: bool, accepted: bool, visits: int, pinned: bool, alive: Set[int]}
  var s: State
  action init = {
    nondet live = Set(Set(), Set(0), Set(1), Set(0, 1)).oneOf()
    nondet closed = Set(false, true).oneOf()
    nondet token = Set(false, true).oneOf()
    s' = {phase: 0, closed: closed, live: live, token: token,
      required: Set(), covered: Set(), dirty: Set(),
      firstValid: false, accepted: false, visits: 0, pinned: false, alive: live}
  }
  action gather = all {s.phase == 0,
    val required = if (s.closed) s.live.union(shared) else complete
    val covered = if (BUG == "dropLive") required.exclude(Set(0))
      else if (BUG == "openWeak" and not(s.closed)) s.live.union(shared)
      else required
    s' = s.with("phase", 1).with("required", required).with("covered", covered)}
  action first = all {s.phase == 1,
    val tokenOK = not(s.closed) or s.live == Set() or s.token or BUG == "missing"
    s' = s.with("phase", if (tokenOK) 2 else 4).with("firstValid", tokenOK)
      .with("pinned", tokenOK)
      .with("visits", if (BUG == "repeat" and s.closed)
        s.covered.size() + s.live.size() * shared.size() else s.covered.size())}
  action effect = {
    nondet changed = complete.union(Set(-1)).oneOf()
    nondet collect = Set(false, true).oneOf()
    all {s.phase == 2,
      s' = s.with("phase", 3).with("dirty", if (changed == -1) Set() else Set(changed))
        .with("alive", if (collect and BUG == "noPin") Set() else s.alive)}
  }
  action final = all {s.phase == 3,
    s' = s.with("phase", 4)
      .with("pinned", BUG == "retain")
      .with("accepted", s.firstValid and
        (BUG == "skipFinal" or s.dirty.intersect(s.covered) == Set()))}
  action terminal = all {s.phase == 4, s' = s}
  action step = any {gather, first, effect, final, terminal}
  val Current = not(s.accepted) or s.dirty.intersect(s.required) == Set()
  val Complete = s.phase == 0 or s.covered == s.required
  val LiveToken = not(s.accepted and s.closed) or s.live == Set() or s.token
  val BatchWork = s.phase < 2 or s.visits == s.covered.size()
  val LiveRoots = s.phase != 3 or s.live.subseteq(s.alive)
  val Released = s.phase != 4 or not(s.pinned)
  val RejectAll = not(s.accepted)
  val safety = Current and Complete and LiveToken and BatchWork and LiveRoots and Released
}
module WitnessReplay { import WitnessReplayModel(BUG = "none").* }
