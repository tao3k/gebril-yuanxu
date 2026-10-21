// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RootChild_parent {
  import RootChildModel(BUG = "parent").* from "./RootChild"
}
