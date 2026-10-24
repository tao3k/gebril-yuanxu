// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module GraphOperations {
  const BUG: str
  // Standard graph facts. 3 and 4 have the same local name in different paths.
  var pc: int
  var live: Set[int]
  var edges: Set[(int, int)]
  var values: int -> List[int]
  var applied: bool
  var changedPasses: int
  var convergenceClaim: bool
  pure val initialValues = Set(0,1,2,3,4,5).mapBy(n =>
    if (n == 0) List(1) else if (n == 5) List(3) else List())
  pure def appendDistinct(base: List[int], extra: List[int]): List[int] =
    extra.foldl(base, (out, value) => if (out.indices().exists(i => out.nth(i) == value)) out else out.append(value))
  // Independent explicit expected fixtures after each ordered operation.
  pure def rootExpected(pass: int): List[int] =
    if (pass == 0) List(1) else if (pass == 1) List(9,1)
    else if (pass < 7) List(9,1,2) else if (pass == 7) List(9,2)
    else if (pass == 8) List(6) else List(6,9)
  pure def liveExpected(pass: int): Set[int] =
    if (pass < 4) Set(0,1,2,3,4) else if (pass == 4) Set(0,2,4)
    else Set(0,1,2,4,5)
  pure def edgesExpected(pass: int): Set[(int,int)] =
    if (pass < 4) Set((0,1),(0,2),(1,3),(2,4))
    else if (pass == 4) Set((0,2),(2,4))
    else Set((0,1),(0,2),(1,5),(2,4))
  action init = all {
    pc' = 0, live' = liveExpected(0), edges' = edgesExpected(0),
    values' = initialValues, applied' = false, changedPasses' = 0,
    convergenceClaim' = false
  }
  action applyNext = all {
    pc < 9,
    pc' = pc + 1,
    live' = if (pc == 3) live.exclude(if (BUG == "orphanDelete") Set(1) else Set(1,3))
            else if (pc == 4) live.union(Set(1,5)) else live,
    edges' = if (pc == 3) edges.filter(e => e._1 != 1 and e._2 != 1 and e._2 != 3)
             else if (pc == 4) edges.union(Set((0,1),(1,5))) else edges,
    values' = if (pc == 0) values.set(0, appendDistinct(List(9), values.get(0)))
      else if (pc == 1) values.set(0, if (BUG == "reverseOrder")
        appendDistinct(List(2,1), values.get(0)) else appendDistinct(values.get(0), List(2,1)))
      else if (pc == 2) values.set(if (BUG == "wrongTarget") 4 else 3, List(7))
      else if (pc == 4) values.set(1, List()).set(5, List(3))
      else if (pc == 5) values.set(5, appendDistinct(values.get(5), List(8)))
      else if (pc == 6) values.set(0, values.get(0).foldl(List(), (out, v) => if (v == 1) out else out.append(v)))
      else if (pc == 7) values.set(0, List(6))
      else if (pc == 8) values.set(0, appendDistinct(values.get(0), List(9)))
      else values,
    applied' = false, changedPasses' = 0, convergenceClaim' = false
  }
  action finish = all {
    pc == 9, not(applied), pc' = pc, live' = live, edges' = edges,
    values' = if (BUG == "replay") values.set(0, appendDistinct(List(9), values.get(0))) else values,
    applied' = true, changedPasses' = 1,
    convergenceClaim' = BUG == "fixedPoint"
  }
  action terminal = all {
    applied, pc' = pc, live' = live, edges' = edges, values' = values,
    applied' = applied, changedPasses' = changedPasses, convergenceClaim' = convergenceClaim
  }
  action step = any { applyNext, finish, terminal }
  val OrderedPayload = values.get(0) == rootExpected(pc)
  val PathIdentity = values.get(4) == List() and (pc < 3 or values.get(3) == List(7))
  val StructuralClosure = live == liveExpected(pc) and edges == edgesExpected(pc) and
    edges.forall(e => live.contains(e._1) and live.contains(e._2))
  val InsertThenTarget = pc < 6 or values.get(5) == List(3,8)
  val HonestReceipt = not(convergenceClaim) and (applied implies pc == 9 and changedPasses == 1)
  val safety = OrderedPayload and PathIdentity and StructuralClosure and InsertThenTarget and HonestReceipt
}
