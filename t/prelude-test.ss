;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test)
(export prelude-test)

;; The public root prelude supplies POO bindings without an explicit POO import.
(begin-syntax
  (begin-syntax (def fixture-port 5440))
  (defsyntax (port-literal stx) (datum->syntax (stx-car stx) fixture-port))
  (def expected-port (port-literal)))
(defsyntax (expected-port-literal stx) (datum->syntax (stx-car stx) expected-port))

(def prelude-test
  (test-suite "Yuanxu package prelude"
    (test-case "ordinary values and prototype refinement"
      (.def Baseline commands: '("gerbil" "build") port: 5432)
      (.def (Release @ Baseline) port: 5440)
      (check-equal? (.get Release port) (expected-port-literal))
      (check-equal? (.get Release commands) '("gerbil" "build"))
      (check-equal? (.get Baseline port) 5432))))
