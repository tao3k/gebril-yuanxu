// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module AuthoringStageModel {
  const BUG: str
  type State = {phase: int, fieldsOK: bool, permits: bool, revision: int,
    checkedRevision: int, checks: int, subject: int, checked: bool,
    invalidAdmission: bool, visible: bool}
  var s: State
  action init = {
    nondet valid = Set(false, true).oneOf()
    s' = {phase: 0, fieldsOK: valid, permits: true, revision: 0,
      checkedRevision: -1, checks: 0, subject: 1, checked: false,
      invalidAdmission: false, visible: false}
  }
  // Construction supplies a fresh candidate, not evidence or permission.
  action construct = all {s.phase == 0, s' = s.with("phase", 1)}
  action changeContract = all {s.phase == 1 or s.phase == 2,
    s' = s.with("revision", 1).with("permits", false)}
  action admit = all {s.phase == 1,
    val valid = s.fieldsOK and s.permits
    val allowed = BUG == "skipAdmission" or
      (s.fieldsOK and (s.permits or BUG == "oldContract"))
    s' = s.with("phase", if (allowed) 2 else 3)
      .with("checked", allowed).with("checkedRevision", s.revision)
      .with("checks", if (BUG == "skipAdmission") 0 else 1)
      .with("subject", if (BUG == "rawSubject") 1 else 2)
      .with("invalidAdmission", allowed and not(valid))
  }
  action publish = all {s.phase == 2,
    val fresh = s.checkedRevision == s.revision
    s' = s.with("phase", 3).with("visible", fresh or BUG == "skipCommit")}
  action terminal = all {s.phase == 3, s' = s}
  action step = any {construct, changeContract, admit, publish, terminal}
  val BoundaryChecked = not(s.checked) or s.checks == 1
  val ValidAdmission = not(s.invalidAdmission)
  val CheckedSubject = not(s.checked) or s.subject == 2
  val CurrentPublication = not(s.visible) or
    (s.checked and s.permits and s.fieldsOK and s.checkedRevision == s.revision)
  val RejectAll = not(s.visible)
  val safety = BoundaryChecked and ValidAdmission and CheckedSubject and CurrentPublication
}
module AuthoringStage {
  import AuthoringStageModel(BUG = "none").*
}
