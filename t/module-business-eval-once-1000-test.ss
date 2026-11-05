;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-business-eval-once-1000-test)
(def module-business-eval-once-1000-test
  (test-suite "One cold business EVAL in a real thousand-module namespace"
    (declaration-scale-case "one business .get includes first admission, scopes and value"
      1000 BusinessEvalOnceFixture)))
