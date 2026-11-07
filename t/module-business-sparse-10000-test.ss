;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-business-sparse-10000-test)
(def module-business-sparse-10000-test
  (test-suite "Sparse business demand in a real ten-thousand-module catalog"
    (declaration-scale-case "one first business read" 10000 SparseBusinessEvalFixture)
    (declaration-scale-case "directory, admission and scopes measured separately"
      10000 SparseBusinessAttributionFixture)))
