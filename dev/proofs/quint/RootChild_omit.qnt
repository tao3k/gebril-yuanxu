// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RootChild_omit {
  import RootChildModel(BUG = "omit").* from "./RootChild"
}
