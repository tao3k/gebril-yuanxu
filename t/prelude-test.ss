;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/misc/process run-process)
        (only-in :std/misc/ports read-all-as-string))
(export prelude-test)

;; The public root prelude supplies POO bindings without an explicit POO import.
(begin-syntax
  (begin-syntax (def fixture-port 5440))
  (defsyntax (port-literal stx) (datum->syntax (stx-car stx) fixture-port))
  (def expected-port (port-literal)))
(defsyntax (expected-port-literal stx) (datum->syntax (stx-car stx) expected-port))

(def (consumer-output file)
  (def source
    (path-expand (string-append "fixtures/prelude-consumer/" file)
                 (path-directory (this-source-file))))
  (run-process
    (list "gxi" "-:max-heap=1G,debug=q" "-e"
          (object->string `(import ,source)))
    stdout-redirection: #t coprocess: read-all-as-string))

(def prelude-test
  (test-suite "Yuanxu package prelude"
    (test-case "ordinary downstream prelude does not load the Module System"
      (check-equal? (string-contains (consumer-output "ordinary.ss") "PRELUDE-INERT-OK") 0))
    (test-case "public declaration entry preserves init exports without source demand"
      (check-equal? (string-contains (consumer-output "init.ss") "PRELUDE-INIT-OK") 0))
    (test-case "ordinary values and prototype refinement"
      (.def Baseline commands: '("gerbil" "build") port: 5432)
      (.def (Release @ Baseline) port: 5440)
      (check-equal? (.get Release port) (expected-port-literal))
      (check-equal? (.get Release commands) '("gerbil" "build"))
      (check-equal? (.get Baseline port) 5432))))
