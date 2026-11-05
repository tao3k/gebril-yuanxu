;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-runtime-values-10000-test)
(def module-runtime-values-10000-test
  (test-suite "Demanded values in a real ten-thousand-module namespace"
    (declaration-scale-case "ten thousand registered modules: first, hot and incremental value" 10000 RuntimeValueFixture)))
