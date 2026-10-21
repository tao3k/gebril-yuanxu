// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module PublicationReadsModel {
  const BUG: str
  // 0 and 3 can share a receiver/key but are distinct native read tokens.
  // Dependencies are unmodified, including a callback-only Contract token 4.
  pure val roots = List(0, 1, 0, 2, 1, 3)
  pure val dependencies = Map(0 -> Set(4), 1 -> Set(), 2 -> Set(4),
    3 -> Set(), 4 -> Set())
  pure val original = roots.foldl(Set(), (out, node) => out.union(Set(node)))
  pure val required = original.union(Set(4))
  var phase: int
  var retained: Set[int]
  var changed: Set[int]
  var events: int
  var accepted: bool
  action init = all {
    phase' = 0, retained' = Set(), changed' = Set(), events' = 0,
    accepted' = false
  }
  action finish = all {
    phase == 0,
    // A failing callback keeps precisely the same support, then rethrows.
    nondet failed = Set(false, true).oneOf()
    retained' = if (BUG == "byKey") original.exclude(Set(3))
      else if (BUG == "failure" and failed) Set() else original,
    events' = if (BUG == "observers") original.size() else roots.length(),
    phase' = 1, changed' = changed, accepted' = false
  }
  action mutate = all {
    phase == 1,
    nondet node = required.union(Set(-1)).oneOf()
    changed' = if (node == -1) Set() else Set(node),
    phase' = 2, retained' = retained, events' = events, accepted' = false
  }
  action publish = all {
    phase == 2,
    val suffix = retained.fold(Set(), (out, n) => out.union(dependencies.get(n)))
    val checked = if (BUG == "suffix") retained else retained.union(suffix)
    accepted' = (BUG == "skipGuard" or checked.intersect(changed) == Set()),
    phase' = 3, retained' = retained, changed' = changed, events' = events
  }
  action terminal = all { phase == 3, phase' = phase, retained' = retained,
    changed' = changed, events' = events, accepted' = accepted }
  action step = any { finish, mutate, publish, terminal }
  val Complete = phase == 0 or retained == original
  val AllEvents = phase == 0 or events == roots.length()
  val Current = not(accepted) or required.intersect(changed) == Set()
  val RejectAll = not(accepted)
  val safety = Complete and AllEvents and Current
}
module PublicationReads { import PublicationReadsModel(BUG = "none").* }
