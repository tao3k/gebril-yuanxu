;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-runtime-selection-10000-test)
(def module-runtime-selection-10000-test
  (test-suite "Complete unobserved ten-thousand-declaration admission"
    (declaration-scale-case "ten thousand complete selected declarations" 10000 RuntimeSelectionFixture)))
