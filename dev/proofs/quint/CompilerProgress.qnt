// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CompilerProgressModel {
  const REPEAT: bool
  // Clocks are abstract ticks. The parent owns both limits independently
  // of the child's prepared-specification receipt and eventual exit.
  type State = {now: int, last: int, ready: bool, received: bool, invalid: bool}
  var s: State
  action init = { s' = {now: 0, last: 0, ready: false, received: false, invalid: false} }
  action tick = all { s.now < 6, s' = s.with("now", s.now + 1) }
  action prepared = all { not(s.ready), s' = s.with("ready", true) }
  action receive = {
    val live = s.now < 5 and s.now - s.last < 2
    val refresh = s.ready and live and (not(s.received) or REPEAT)
    s' = if (refresh)
      s.with("last", s.now).with("received", true).with("invalid", s.invalid or s.received)
    else s
  }
  action step = any { tick, prepared, receive }
  val safety = not(s.invalid)
}
module CompilerProgress {
  import CompilerProgressModel(REPEAT = false).*
}
