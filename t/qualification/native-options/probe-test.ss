;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :yuanxu-native-options/support)
(export probe-test)
(def probe-test
  (test-suite "native compiler options"
    (test-case "real compiled support" (check-equal? native-value 7))))
