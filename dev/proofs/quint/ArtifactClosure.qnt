// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ArtifactClosureModel {
  const BUG: str
  var phase: int
  var change: str
  var a: bool
  var b: bool
  var accepted: bool
  var cold: int
  var parent: int
  var unused: int
  action init = {
    nondet selected = Set("none", "binary", "dependency", "higher-object", "metadata", "old-body", "input", "loaded").oneOf()
    nondet ra = Set(false, true).oneOf()
    nondet rb = Set(false, true).oneOf()
    all {phase' = 0, change' = selected, a' = ra, b' = rb,
      accepted' = false, cold' = 0, parent' = 5432, unused' = 0}
  }
  val unchanged = change == "none"
    or (BUG == "omitDependency" and change == "dependency")
    or (BUG == "ignoreResolution" and change == "higher-object")
    or (BUG == "trustOldBody" and change == "old-body")
    or (BUG == "skipInput" and change == "input")
    or (BUG == "ignoreLoaded" and change == "loaded")
  action check = all {phase == 0, phase' = 1,
    accepted' = (unchanged and a and (b or BUG == "dropB")),
    change' = change, a' = a, b' = b, cold' = cold, parent' = parent, unused' = unused}
  action invoke = all {phase == 1, phase' = 2,
    cold' = if (accepted and change != "none") 5440 else if (accepted) 5432 else 0,
    parent' = if (BUG == "parent") 5440 else parent,
    unused' = if (BUG == "eager") 1 else unused,
    accepted' = accepted, change' = change, a' = a, b' = b}
  action terminal = all {phase == 2, phase' = phase, change' = change,
    a' = a, b' = b, accepted' = accepted, cold' = cold, parent' = parent, unused' = unused}
  action step = any {check, invoke, terminal}
  val NoChangedAdmission = not(accepted) or change == "none"
  val NoPoison = cold != 5440
  val BothRequirements = not(accepted) or (a and b)
  val ParentCache = parent == 5432
  val LazyBranch = unused == 0
  val RejectAll = not(accepted)
  val safety = NoChangedAdmission and NoPoison and BothRequirements and ParentCache and LazyBranch
}
module ArtifactClosure { import ArtifactClosureModel(BUG = "none").* }
