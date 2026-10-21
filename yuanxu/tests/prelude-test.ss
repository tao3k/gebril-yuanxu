;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test)
(export prelude-test)

;; gerbil.pkg supplies the prelude: no explicit POO import is needed.
(def prelude-test
  (test-suite "Yuanxu package prelude"
    (test-case "ordinary values and prototype refinement"
      (.def Baseline commands: '("gerbil" "build") port: 5432)
      (.def (Release @ Baseline) port: 5440)
      (check-equal? (.get Release port) 5440)
      (check-equal? (.get Release commands) '("gerbil" "build"))
      (check-equal? (.get Baseline port) 5432))))
