;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        "./qualification/module-bootstrap/objects.ss")
(export package-bootstrap-test)

(def package-bootstrap-test
  (test-suite "Yuanxu source-only build bootstrap"
    (test-case "build spec needs neither an installed library nor installed language entry"
      (def lib (path-expand "lib" (.get Fixture state)))
      (check-equal? (.get Fixture cold) #t)
      (check-equal? (file-exists? (path-expand "yuanxu" lib)) #f)
      (check-equal? (file-exists? (path-expand "tao3k/yuanxu" lib)) #f)
      (def result (.call Build .run "spec"))
      (unless (zero? (.get result status))
        (display (.get result output))
        (error "source-only build spec failed" (.get result status)))
      (def spec (call-with-input-string (.get result output) read))
      (check-equal? (list? spec) #t)
      (check-equal? (length (filter (lambda (entry) (equal? (cadr entry) "prelude")) spec)) 1)
      ;; Spec construction must not silently compile or install either namespace.
      (check-equal? (file-exists? (path-expand "yuanxu" lib)) #f)
      (check-equal? (file-exists? (path-expand "tao3k/yuanxu" lib)) #f))))
