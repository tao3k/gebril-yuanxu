;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-runtime-attribution-1000-test)
(def module-runtime-attribution-1000-test
  (test-suite "Unobserved thousand-module admission, replay and scope attribution"
    (declaration-scale-case "same 180-second Case, separated real phases"
      1000 RuntimeAttributionFixture)))
