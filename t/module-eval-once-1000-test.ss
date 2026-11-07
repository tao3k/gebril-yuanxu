;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-eval-once-1000-test)
(def module-eval-once-1000-test
  (test-suite "One explicitly bounded thousand-declaration EVAL call"
    (declaration-scale-case "one complete declaration expression, cold and repeated"
      1000 ModuleEvalOnceFixture)))
