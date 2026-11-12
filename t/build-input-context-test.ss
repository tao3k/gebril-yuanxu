;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil/runtime/loader load-path set-load-path!)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/building/source-package call-with-build-input-path))
(export build-input-context-test)
(def (with-input-path paths action)
  (def previous (load-path))
  (dynamic-wind (lambda () (set-load-path! paths)) action
                (lambda () (set-load-path! previous))))
(def build-input-context-test
  (test-suite "Init-owned compiler input context"
    (test-case "output-first callers retain input order and restore runtime order"
      (call-with-temporary-directory "build-input-context-"
        (lambda (root)
          (def output (path-expand "output" root))
          (def one (path-expand "input-one" root))
          (def two (path-expand "input-two" root))
          (def checkout (path-expand "declared-checkout" root))
          (for-each create-directory* (list output one two checkout))
          (with-input-path (list output one two)
            (lambda ()
              (let-values (((a b)
                (call-with-build-input-path output
                  (lambda ()
                    (check-equal? (load-path) (list one two output))
                    ;; Nested scopes and the normal standard output fallback work.
                    (call-with-build-input-path output
                      (lambda () (check-equal? (load-path) (list one two output))))
                    (values 1 2)))))
                (check-equal? (list a b) '(1 2)))
              (call-with-build-input-path output
                (lambda ()
                  (check-equal? (load-path) (list two checkout one output)))
                source-roots: (list two checkout checkout))
              (check-equal? (load-path) (list output one two))))
          (with-input-path (list one two)
            (lambda ()
              (call-with-build-input-path output
                (lambda ()
                  (check-equal? (load-path) (list checkout one two output)))
                source-roots: (list checkout))
              (check-equal? (load-path) (list one two))
              (call-with-build-input-path output
                (lambda () (set-load-path! (cons checkout (load-path))))
                make-source: checkout)
              (check-equal? (load-path) (list one two))
              (check-exception
                (call-with-build-input-path output
                  (lambda () (set-load-path! (cons two (load-path))))
                  make-source: checkout)
                error?)
              (check-equal? (load-path) (list one two)))))))
    (test-case "path mutation refuses admission and restores the caller"
      (call-with-temporary-directory "build-input-refusal-"
        (lambda (root)
          (def output (path-expand "output" root))
          (def input (path-expand "input" root))
          (for-each create-directory* (list output input))
          (with-input-path (list output input)
            (lambda ()
              (def refused? #f)
              (check-exception
                (call-with-build-input-path output
                  (lambda () (set-load-path! (list output input)))
                  (lambda () (set! refused? #t) (error "refused"))) error?)
              (check-equal? refused? #t)
              (check-equal? (load-path) (list output input))
              (set! refused? #f)
              (check-exception
                (call-with-build-input-path output
                  (lambda ()
                    (set-load-path! (list output input))
                    (error "author failure after mutation"))
                  (lambda () (set! refused? #t) (error "refused"))) error?)
              (check-equal? refused? #t)
              (check-equal? (load-path) (list output input))
              (check-exception (call-with-build-input-path output (lambda () (error "author failure"))) error?)
              (check-equal? (load-path) (list output input)))))))))
