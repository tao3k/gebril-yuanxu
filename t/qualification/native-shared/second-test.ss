;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :yuanxu-native-shared/support)
(export second-test)
(def second-test (test-suite "second" (test-case "own verdict" (check-equal? value 7))))
