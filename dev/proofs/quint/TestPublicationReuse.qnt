// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Private packet sharing is not sharing successful source admission. This
// finite projection starts after the public codec accepted the retained bytes.
module TestPublicationReuseModel {
  const BUG: str
  var r: {phase: int, decodes: int, source: int, approval: int, matches: bool,
    a: bool, b: bool, accepted: bool, parent: int, unused: int}
  action init = {
    nondet matches = Set(false, true).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {r' = {phase: 0, decodes: 1, source: 1, approval: 1, matches: matches,
      a: a, b: b, accepted: false, parent: 5432, unused: 0}}
  }
  action effect = {
    nondet source = Set(1, 2).oneOf()
    nondet approval = Set(1, 2).oneOf()
    all {r.phase == 0, r' = r.with("phase", 1).with("source", source).with("approval", approval)}
  }
  action finish = all {r.phase == 1, r' = r.with("phase", 2).with("accepted",
    (r.matches or BUG == "packet") and r.a and r.b and
    ((r.source == 1 and r.approval == 1) or BUG == "memoAdmission"))}
  action terminal = all {r.phase == 2, r' = r}
  action step = any {effect, finish, terminal}
  val Fresh = not(r.accepted) or (r.source == 1 and r.approval == 1)
  val Bound = not(r.accepted) or r.matches
  val Both = not(r.accepted) or (r.a and r.b)
  val Isolated = r.parent == 5432 and r.unused == 0
  val DecodeOnce = r.decodes == 1
  val RejectAll = not(r.accepted)
  val safety = Fresh and Bound and Both and Isolated and DecodeOnce
}

module TestPublicationReuse { import TestPublicationReuseModel(BUG = "none").* }
