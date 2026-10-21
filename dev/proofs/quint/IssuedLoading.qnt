// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module IssuedLoadingModel {
  const BUG: str
  type State = {phase: int, attack: str, issuerRecord: int, issuerCode: int,
    record: int, code: int, dependency: int, path: int, privateCode: int,
    denied: bool, allowed: bool, checkedCode: int, loaded: int,
    cachedAllowed: bool, a: bool, b: bool, published: bool, parent: int, unused: int}
  var s: State
  action init = {
    nondet attack = (if (BUG == "poolWriter")
      Set("late-private") else Set("none", "both", "higher", "dependency", "after-copy", "private-before", "late-public", "cached-record")).oneOf()
    nondet a = Set(false, true).oneOf()
    nondet b = Set(false, true).oneOf()
    all {s' = {phase: 0, attack: attack, issuerRecord: 1, issuerCode: 5432,
      record: 1, code: 5432, dependency: 1, path: 1, privateCode: 0,
      denied: false, allowed: false, checkedCode: 0, loaded: 0, cachedAllowed: false,
      a: a, b: b, published: false, parent: 5432, unused: 0}}
  }
  action prepare = all {s.phase == 0,
    s' = s.with("phase", 1)
      .with("record", if (s.attack == "both") 2 else 1)
      .with("code", if (s.attack == "both") 5440 else 5432)
      .with("path", if (s.attack == "higher") 2 else 1)
      .with("dependency", if (s.attack == "dependency") 2 else 1)}
  val recordMatches = s.record == s.issuerRecord or BUG == "trustSidecar"
  val codeMatches = s.code == s.issuerCode or BUG == "trustSidecar"
  val current = recordMatches and codeMatches and s.path == 1 and s.dependency == 1
  action copy = all {s.phase == 1,
    s' = s.with("phase", 2).with("denied", not(current))
      .with("privateCode", if (current) s.code else 0)}
  action replace = all {s.phase == 2,
    s' = s.with("phase", 3)
      .with("code", if (s.attack == "after-copy") 5440 else s.code)
      .with("privateCode", if (s.attack == "private-before") 5440 else s.privateCode)}
  action handoff = all {s.phase == 3,
    s' = s.with("phase", 4).with("checkedCode", s.code)
      .with("allowed", not(s.denied) and
        ((current and (s.privateCode == s.issuerCode or BUG == "trustSidecar")) or BUG == "skipHandoff"))}
  action consume = all {s.phase == 4,
    s' = s.with("phase", 5)
      .with("code", if (s.attack == "late-public") 5440 else s.code)
      .with("privateCode", if (s.attack == "late-private") 5440 else s.privateCode)
      .with("loaded", if (not(s.allowed)) 0 else
        if (s.attack == "late-private" or (BUG == "publicPath" and s.attack == "late-public")) 5440 else s.privateCode)
      .with("published", s.allowed and s.a and (s.b or BUG == "dropB"))
      .with("parent", if (BUG == "parent") 5440 else s.parent)
      .with("unused", if (BUG == "eager") 1 else 0)}
  action cached = all {s.phase == 5,
    s' = s.with("phase", 6)
      .with("record", if (s.attack == "cached-record") 2 else s.record)
      .with("cachedAllowed", s.allowed and (s.attack != "cached-record" or BUG == "skipCache"))}
  action terminal = all {s.phase == 6, s' = s}
  action step = any {prepare, copy, replace, handoff, consume, cached, terminal}
  val ByteSafety = s.loaded == 0 or s.loaded == s.issuerCode
  val HandoffCurrent = not(s.allowed) or s.checkedCode == s.issuerCode
  val CacheAuthority = not(s.cachedAllowed) or s.record == s.issuerRecord
  val BothRequirements = not(s.published) or (s.a and s.b)
  val ParentCache = s.parent == 5432
  val LazyBranch = s.unused == 0
  val LatestPath = not(s.allowed) or s.code == s.issuerCode
  val RejectAll = not(s.allowed)
  val safety = ByteSafety and HandoffCurrent and CacheAuthority and BothRequirements and ParentCache and LazyBranch
}
module IssuedLoading { import IssuedLoadingModel(BUG = "none").* }
