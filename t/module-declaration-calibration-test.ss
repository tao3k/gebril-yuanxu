;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test "./qualification/module-scale/fixture.ss")
(export module-declaration-calibration-test)
(def module-declaration-calibration-test
  (test-suite "Native declaration calibration"
    (declaration-scale-case "sixteen real module declarations" 16)))
