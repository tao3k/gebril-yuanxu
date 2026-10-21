// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite callback schedule; not a native dispatch or performance model.
module CarrierReturnModel {
  const BUG: str
  var phase: int
  var valid: bool
  var executed: bool
  action init = all {phase' = 0, valid' = true, executed' = false}
  // The constructor has already checked its default. A public hook can edit
  // that SAME object; construction-time validity is not a return certificate.
  action callback = {
    nondet edit = Set(false, true).oneOf()
    all {phase == 0, phase' = 1, valid' = not(edit), executed' = executed}}
  action returned = all {phase == 1,
    phase' = 2, valid' = valid,
    executed' = (valid or BUG == "skipReturn")}
  action terminal = all {phase == 2, phase' = phase, valid' = valid,
    executed' = executed}
  action step = any {callback, returned, terminal}
  val ValidExecution = not(executed) or valid
  val RejectAll = not(executed)
}
module CarrierReturn {
  import CarrierReturnModel(BUG = "none").*
}
