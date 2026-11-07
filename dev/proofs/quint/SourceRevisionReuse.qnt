// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SourceRevisionReuse {
  // The consumer's file stays the same. Its selection support can change.
  var phase: int
  var selection: bool
  var retained: bool
  var approved: bool
  action init = all {
    phase' = 0, selection' = false, retained' = false, approved' = false,
  }
  action edit = all {
    phase == 0, phase' = 1, selection' = true, retained' = retained, approved' = false,
  }
  action refresh = all {
    phase == 1, phase' = 2, selection' = selection, retained' = selection, approved' = true,
  }
  action reuseByFileOnly = all {
    phase == 1, phase' = 2, selection' = selection, retained' = retained, approved' = true,
  }
  action finish = all {
    phase == 2, phase' = phase, selection' = selection, retained' = retained, approved' = approved,
  }
  action step = any { edit, refresh, finish }
  action unsafeStep = any { edit, reuseByFileOnly, finish }
  val Current = not(approved) or retained == selection
}

// All traces retain the same source bytes across role resolution. The new
// reader may still resolve a different role value. A callback can then edit
// the live source before the successor publishes.
module ResolvedRoleReuse {
  var phase: int
  var role: int
  var payloadRole: int
  var checked: int
  var live: int
  var published: bool

  action init = all {
    phase' = 0, role' = 0, payloadRole' = 0,
    checked' = 0, live' = 0, published' = false,
  }
  action resolve = {
    nondet nextRole = Set(0, 1).oneOf()
    all {
      phase == 0, phase' = 1, role' = nextRole,
      payloadRole' = payloadRole, checked' = live, live' = live, published' = false,
    }
  }
  action construct = all {
    phase == 1, payloadRole != role, phase' = 2, role' = role, payloadRole' = role,
    checked' = checked, live' = live, published' = false,
  }
  action reuseByBytes = all {
    phase == 1, phase' = 2, role' = role, payloadRole' = payloadRole,
    checked' = checked, live' = live, published' = false,
  }
  action reuse = all {
    payloadRole == role, reuseByBytes,
  }
  action callback = {
    nondet nextRevision = Set(0, 1).oneOf()
    all {
      phase == 2, phase' = 3, role' = role, payloadRole' = payloadRole,
      checked' = checked, live' = nextRevision, published' = false,
    }
  }
  action publish = all {
    phase == 3, phase' = 4, role' = role, payloadRole' = payloadRole,
    checked' = checked, live' = live, published' = (checked == live),
  }
  action step = any { resolve, construct, reuse, callback, publish }
  action unsafeStep = any { resolve, reuseByBytes, callback, publish }
  val Current = not(published) or (payloadRole == role and checked == live)
}
