// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Ordered identity sequences model a private vector; not physical GC layout.
module IssuerSequenceModel {
  const BUG: str
  var s: {done: bool, public: List[int], saved: List[int], inspected: List[int],
    accepted: bool, expected: bool, snapshot: bool}
  action init = s' = {done: false, public: List(), saved: List(), inspected: List(),
    accepted: false, expected: false, snapshot: true}
  action verify = {
    nondet edited = Set(false, true).oneOf()
    nondet inspectEdited = Set(false, true).oneOf()
    nondet empty = Set(false, true).oneOf()
    val original = if (empty) List() else List(1, 2, 1)
    val public = if (edited) List(1, 2) else original
    val private = if (BUG == "drop") List(1, 2)
      else if (BUG == "order") List(1, 1, 2)
      else if (BUG == "alias" and inspectEdited) List(9)
      else original
    all {not(s.done), s' = {done: true, public: public, saved: private,
      inspected: if (inspectEdited) List(9) else original,
      accepted: public == private, expected: public == original,
      snapshot: private == original}}
  }
  action terminal = all {s.done, s' = s}
  action step = any {verify, terminal}
  val Authentication = not(s.done) or s.accepted == s.expected
  val OrderedSnapshot = s.snapshot
  val safety = Authentication and OrderedSnapshot
}
module IssuerSequence { import IssuerSequenceModel(BUG = "none").* }
