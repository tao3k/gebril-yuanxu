// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SourcePrefixModel {
  const BUG: str
  // Source identities in the SAME Graph: owner, imported support, compiler
  // policy and a Schema/Contract source. These are not Contract-name labels.
  pure val required = Set(0, 1, 2, 3)
  pure val checked = if (BUG == "drop") required.exclude(Set(3)) else required
  pure def current(dirty: Set[int]): bool = dirty.intersect(checked) == Set()
  type State = {phase: int, closed: bool, dirty: Set[int],
    entryDirty: Set[int], entryReads: int, started: bool,
    metadataChecked: bool, checkedSubject: int, publishedSubject: int,
    accepted: bool, held: bool}
  var s: State
  action init = {
    nondet closed = Set(false, true).oneOf()
    nondet initial = required.union(Set(-1)).oneOf()
    s' = {phase: 0, closed: closed, dirty: if (initial == -1) Set() else Set(initial), entryDirty: Set(),
      entryReads: 0, started: false, metadataChecked: false,
      checkedSubject: -1, publishedSubject: -1, accepted: false, held: false}
  }
  action eligibility = all {
    s.phase == 0,
    // Closed location guards only its metadata/directory projection. An open
    // callback still needs the complete precondition BEFORE it can execute.
    val allowed = s.closed or current(s.dirty)
    s' = s.with("phase", if (allowed) 1 else 8)
      .with("entryReads", if (s.closed) 0 else 1).with("held", allowed)
  }
  action locate = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 1,
      // A certified native directory prefix cannot run a contributor callback.
      // A changed Context takes the open path BEFORE invoking its locator.
      s' = s.with("phase", 2).with("dirty",
        if (s.closed or changed == -1) s.dirty else s.dirty.union(Set(changed))) }
  }
  action readerEntry = {
    // Never mistake the metadata projection for the complete reader support.
    // The first opaque preparation/expansion requires a FULL fresh entry check.
    val reuse = (BUG == "open" and not(s.closed)) or (BUG == "scope" and s.closed)
    val allowed = reuse or current(s.dirty)
    all { s.phase == 2,
      s' = s.with("phase", if (allowed) 3 else 8)
        .with("entryDirty", s.dirty).with("started", allowed)
        .with("entryReads", s.entryReads + (if (reuse) 0 else
           if (s.closed and BUG == "repeat") 2 else 1))
        .with("held", allowed) }
  }
  // The pure observation window ENDS before authoring/expansion/initializers.
  action expand = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 3,
      s' = s.with("phase", 4).with("dirty",
        if (changed == -1) s.dirty else s.dirty.union(Set(changed))) }
  }
  action declarationAfter = all {
    s.phase == 4,
    s' = s.with("phase", if (current(s.dirty)) 5 else 8)
      .with("held", current(s.dirty))
  }
  // Actual .def metadata may still be cold after declarationAfter. The
  // maintained structural predicate can force contributor getters; passing
  // that predicate proves shape, not absence of source effects.
  action metadata = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 5,
      s' = s.with("phase", 6).with("dirty",
        if (changed == -1 or BUG == "contextAfterCheck") s.dirty else s.dirty.union(Set(changed)))
        // Distinct reference 1 represents a normalizer's returned receiver;
        // raw input 0 must not be substituted after successful admission.
        .with("metadataChecked", true).with("checkedSubject", 1) }
  }
  // Even already checked shape does not close Context obligations. This is
  // independent of the earlier getter effect and still needs a fresh tail.
  action admit = {
    nondet changed = required.union(Set(-1)).oneOf()
    all { s.phase == 6,
      s' = s.with("phase", 7).with("dirty",
        if (changed == -1 or BUG == "coldMetadata") s.dirty else s.dirty.union(Set(changed))) }
  }
  action publish = all {
    s.phase == 7,
    s' = s.with("phase", 8)
      .with("publishedSubject", if (BUG == "rawSubject") 0 else s.checkedSubject)
      .with("accepted", BUG == "carry" or BUG == "coldMetadata" or
        BUG == "contextAfterCheck" or current(s.dirty))
      .with("held", BUG == "cleanup")
  }
  action terminate = all {
    s.phase >= 1, s.phase <= 7,
    s' = s.with("phase", 8).with("accepted", false).with("held", BUG == "cleanup")
  }
  action terminal = all { s.phase == 8, s' = s }
  action step = any { eligibility, locate, readerEntry, expand, declarationAfter,
                      metadata, admit, publish, terminate, terminal }
  val EntryCurrent = not(s.started) or s.entryDirty.intersect(required) == Set()
  val PublishedCurrent = not(s.accepted) or s.dirty.intersect(required) == Set()
  val ClosedPrefixOnce = not(s.closed and s.started) or s.entryReads == 1
  val CheckedBeforePublication = not(s.accepted) or s.metadataChecked
  val SameAdmittedSubject = not(s.accepted) or s.publishedSubject == s.checkedSubject
  val Cleanup = s.phase != 8 or not(s.held)
  val RejectAll = not(s.accepted)
  val safety = EntryCurrent and PublishedCurrent and CheckedBeforePublication and SameAdmittedSubject and ClosedPrefixOnce and Cleanup
}
module SourcePrefix {
  import SourcePrefixModel(BUG = "none").*
}
