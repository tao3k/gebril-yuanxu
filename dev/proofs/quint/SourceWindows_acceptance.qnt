// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Expected counterexample to RejectAll: positive safety is not vacuous.
module SourceWindows_acceptance {
  import SourceWindowsModel(BUG = "none").* from "./SourceWindows"
}
