;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Trusted build-job completion, before any selected callback loading.
(import "./artifact-closure")
(def root (path-expand (getenv "CORE_STORE_ROOT")))
(def (datum name) (car (read-forms (path-expand name root))))
(for-each (lambda (entry)
  (unless (equal? (file-digest (car entry)) (cdr entry))
    (error "compiler input changed before job completion" (car entry))))
  (datum "compiler-inputs.ss"))
(unless (equal? (datum "compiler-closure.ss")
               (compiler-code-facts "yuanxu/t/qualification/mop-state/precompiled-stores"
                                    (datum "forbidden-bindings.ss")))
  (error "compiler closure changed before job completion"))
;; These are the outputs of the immediately preceding native GSC job. The
;; policy's dynamic LOAD is a compiler-owned resource edge, not a module edge.
(def resources (map (lambda (name)
  (let (path (path-expand name root)) (cons path (file-digest path))))
  '("store-runtime.scm" "store-runtime.o1" "loader-runtime.scm" "loader-runtime.o1"
    "lib/yuanxu/t/qualification/mop-state/source-loader.scm"
    "lib/yuanxu/t/qualification/mop-state/source-loader.o1"
    "lib/yuanxu/t/qualification/mop-state/source-loader~0.scm"
    "lib/yuanxu/t/qualification/mop-state/source-loader~0.o1")))
(call-with-output-file (list path: (path-expand "resource-inputs.ss" root) truncate: #t)
  (lambda (port) (write resources port)))
(displayln "ARTIFACT-ISSUER: native import closure and compiler resource outputs bound")
(display "RESOURCE-ISSUANCE ") (write resources) (newline)
