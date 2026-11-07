;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation shared by publication suites; no test suite is imported.
(import (only-in :std/test test-suite)
        (only-in :yuanxu/t/qualification/module-publication/controls
                 register-build-support-control-cases!))
(export build-support-control-test)
(def build-support-control-test
  (test-suite "Selected publication controls"
    (register-build-support-control-cases!)))
