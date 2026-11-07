;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :yuanxu-native-shared/support)
(export first-test)
(def first-test (test-suite "first" (test-case "own verdict" (check-equal? value 7))))
