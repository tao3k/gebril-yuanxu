;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-runtime-selection-1000-test)
(def module-runtime-selection-1000-test
  (test-suite "Complete unobserved thousand-declaration admission"
    (declaration-scale-case "one thousand complete selected declarations" 1000 RuntimeSelectionFixture)))
