// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SemanticReadsModel {
  const BUG: str
  // 0 policy, 1 actual Contract, 2 source, 3 Generic generation;
  // 4 invocation frame, 5 effective method. These are identities, not bytes.
  pure val external = Set(0, 1, 2, 3)
  pure val trace = external.union(Set(4, 5))
  var phase: int
  var escaped: bool
  var certified: bool
  var changed: Set[int]
  var published: bool

  val required = if (escaped) external.union(Set(4)) else external
  // An unknown/open callback has no non-escape certificate: keep its trace.
  // This is a specification of a future projection, NOT an implemented filter.
  val projection =
    if (BUG == "policy") required.exclude(Set(0))
    else if (BUG == "contract") required.exclude(Set(1))
    else if (BUG == "source") required.exclude(Set(2))
    else if (BUG == "generic") required.exclude(Set(3))
    else if (BUG == "escape") external
    else if (certified and not(escaped)) external else trace

  action init = all {
    phase' = 0, escaped' = false, certified' = false,
    changed' = Set(), published' = false
  }
  action finish = all {
    phase == 0,
    nondet escape = Set(false, true).oneOf()
    nondet certificate = Set(false, true).oneOf()
    all { phase' = 1, escaped' = escape, certified' = certificate,
          changed' = changed, published' = published }
  }
  action mutate = all {
    phase == 1,
    nondet identity = trace.oneOf()
    all { phase' = 2, changed' = Set(identity), escaped' = escaped,
          certified' = certified, published' = published }
  }
  action publish = all {
    phase == 2, phase' = 3,
    published' = ((BUG == "return") or projection.intersect(changed) == Set()),
    changed' = changed, escaped' = escaped, certified' = certified
  }
  action terminal = all {
    phase == 3, phase' = phase, changed' = changed, escaped' = escaped,
    certified' = certified, published' = published
  }
  action step = any { finish, mutate, publish, terminal }
  val Complete = phase == 0 or required.subseteq(projection)
  val Current = not(published) or required.intersect(changed) == Set()
  val UnknownFallback = phase == 0 or certified or projection == trace
  val RejectAll = phase != 3
  val safety = Complete and Current and UnknownFallback
}
module SemanticReads { import SemanticReadsModel(BUG = "none").* }
