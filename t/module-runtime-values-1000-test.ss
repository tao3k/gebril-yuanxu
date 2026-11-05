;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-runtime-values-1000-test)
(def module-runtime-values-1000-test
  (test-suite "Demanded values in a real thousand-module namespace"
    (declaration-scale-case "one thousand registered modules: first, hot and incremental value" 1000 RuntimeValueFixture)))
