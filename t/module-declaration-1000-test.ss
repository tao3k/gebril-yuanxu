;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-declaration-1000-test)
(def module-declaration-1000-test
  (test-suite "Thousand real module declarations"
    (declaration-scale-case "one thousand real module declarations" 1000)))
