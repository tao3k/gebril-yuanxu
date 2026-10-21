// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReaderProjectionModel {
  const BUG: str
  // Stable native topology: root 0 -> unregistered 2 -> registered 3;
  // another root 4 shares 3. ContextWalk owns traversal order, not this model.
  pure val nodes = Set(0, 2, 3, 4)
  pure def closure(request: int): Set[int] =
    if (request == 2) Set(3, 4) else Set(0, 2, 3)
  type State = {phase: int, request: int, known: Set[int], required: Set[int],
    projected: Set[int], scratch: Set[int], saved: Set[int],
    versions: int -> int, accepted: bool}
  var s: State
  action init = {
    s' = {phase: 0, request: 0, known: Set(0, 3, 4), required: Set(),
      projected: Set(), scratch: Set(), saved: Set(),
      versions: nodes.mapBy(_ => 0), accepted: false}
  }
  action project = all {
    s.phase == 0, s.request < 3,
    val required = closure(s.request).intersect(s.known)
    val projected = if (BUG == "cacheInputs" and s.request == 1) s.saved
      else if (BUG == "cutUnknown" and s.request == 0) Set(0)
      else if (BUG == "dropSource") required.exclude(Set(3)) else required
    s' = s.with("phase", 1).with("required", required)
      .with("projected", projected).with("scratch", closure(s.request))
      .with("saved", if (BUG == "cacheInputs" and s.request == 0) projected else s.saved)
      .with("accepted", false)
  }
  action effect = {
    nondet changed = nodes.union(Set(-1)).oneOf()
    all { s.phase == 1,
      s' = s.with("phase", 2)
        .with("versions", if (changed == -1) s.versions else s.versions.set(changed, 1)) }
  }
  action finish = all {
    s.phase == 2,
    s' = s.with("phase", if (s.request == 2) 3 else 0)
      .with("request", s.request + 1)
      .with("accepted", BUG == "skipGuard" or s.projected.forall(n => s.versions.get(n) == 0))
      .with("scratch", if (BUG == "retain") s.scratch else Set())
      // Registration changes between native demands. A topology snapshot must
      // never become a cached list of input objects from an earlier registry.
      .with("known", s.known.union(Set(2)))
  }
  action terminal = all { s.phase == 3, s' = s }
  action step = any { project, effect, finish, terminal }
  val ExactInputs = s.projected == s.required
  val NoIdleProjection = not(s.phase == 0 or s.phase == 3) or s.scratch == Set()
  val Current = not(s.accepted) or s.required.forall(n => s.versions.get(n) == 0)
  val RetainSources = s.known.contains(3)
  val RejectAll = not(s.accepted)
  val safety = ExactInputs and NoIdleProjection and Current and RetainSources
}
module ReaderProjection { import ReaderProjectionModel(BUG = "none").* }
