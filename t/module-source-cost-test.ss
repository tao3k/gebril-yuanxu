;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Matched runtime IO accounting control; not a timing acceptance gate.
(import :std/test
        (only-in :std/error Error? Error-message)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-observe
                 module-source-admit-current! call-with-collected-module-sources
                 current-module-source-observer call-with-module-source-read-cache)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-source-cost-test)
(def module-source-cost-test
  (test-suite "Source guard accounting"
    (yuanxu-test-case "same real source snapshot and independent fresh reads"
      (displayln "SOURCE-RUNTIME max-heap=" (##get-max-heap))
      (check-equal? (> (##get-max-heap) 0) #t)
      (def expected
        (module-source-read
          (path-expand "../module-system/source/reader.ss" (path-directory (this-source-file)))))
      (call-with-temporary-directory "source-read-allocation"
        (lambda (root)
          (def file (path-expand "reader.ss" root))
          (call-with-output-file file (cut display expected <>))
          (def (checks)
            (let loop ((left 200))
              (unless (zero? left)
                (unless (equal? expected (module-source-read file))
                  (error "changed source during matched read control"))
                (loop (- left 1)))))
          (def (measure name work expected-reads)
            (def reads 0)
            (def stats
              (##exec-stats
                (lambda ()
                  (parameterize ((current-module-source-observer
                                  (lambda (key amount)
                                    (when (eq? key 'reads) (set! reads (+ reads amount))))))
                    (work)))))
            (check-equal? reads expected-reads)
            ;; Exact logical IO work, not an assertion about a non-monotone VM
            ;; accounting field or an unmeasured physical constructor total.
            (displayln "SOURCE-ACCOUNTING " name " reads=" reads
              " characters=" (* reads (string-length expected)) " metrics="
              (filter (lambda (entry) (not (eq? (car entry) 'result))) stats)))
          (measure 'independent checks 200)
          (measure 'pure-window (lambda () (call-with-module-source-read-cache checks)) 1)
          ;; A cached false value is a hit, never a new query. A new pure
          ;; window must nevertheless execute that query independently.
          (def queries 0)
          (def (false-query) (set! queries (+ queries 1)) #f)
          (parameterize ((current-module-source-observer #f))
            (call-with-module-source-read-cache
              (lambda ()
                (check-equal? (module-source-observe false-query) #f)
                (check-equal? (module-source-observe false-query) #f))))
          (check-equal? queries 1)
          (parameterize ((current-module-source-observer #f))
            (call-with-module-source-read-cache
              (lambda () (check-equal? (module-source-observe false-query) #f))))
          (check-equal? queries 2))))
    (yuanxu-test-case "equal-sized source revisions are not interchangeable query inputs"
      (def checks 0)
      (def (read-snapshot rows)
        (set! checks (+ checks 1))
        (cdar rows))
      ;; Distinct snapshots have the same owner path and cardinality. The open
      ;; query must compare their actual values, not substitute those two facts.
      (parameterize ((current-module-source-observer (lambda (_key _amount) (void))))
        (call-with-module-source-read-cache
          (lambda ()
            (check-equal? (module-source-observe read-snapshot '(("types.ss" . "5432"))) "5432")
            (check-equal? (module-source-observe read-snapshot '(("types.ss" . "5440"))) "5440")
            (check-equal? (module-source-observe read-snapshot '(("types.ss" . "5432"))) "5432"))))
      (check-equal? checks 2))
    (yuanxu-test-case "query hit callback failure escapes with its original identity"
      (def failure (gensym 'source-query-hit))
      (def calls 0)
      (def (query) (set! calls (+ calls 1)) 'checked)
      (parameterize ((current-module-source-observer
                      (lambda (key _amount)
                        (when (eq? key 'query-hits) (raise failure)))))
        (call-with-module-source-read-cache
          (lambda ()
            (check-equal? (module-source-observe query) 'checked)
            (check-exception (module-source-observe query) (lambda (cause) (eq? cause failure))))))
      (check-equal? calls 1))
    (yuanxu-test-case "nested source enrollment survives pure byte sharing and independent return checks"
      (call-with-temporary-directory "nested-source-obligations"
        (lambda (root)
          (def path (path-expand "config.ss" root))
          (def (write! text)
            (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
          (write! "5432")
          (def observations (list (cons path "5432")))
          (def outer-current! #f)
          (def inner-current! #f)
          ;; Exercise the normal unobserved batching branch. The nested owner
          ;; must enroll even if the outer owner already checked these bytes.
          (parameterize ((current-module-source-observer #f))
            (call-with-collected-module-sources
              (lambda (outer)
                (set! outer-current! outer)
                (call-with-module-source-read-cache
                  (lambda ()
                    (module-source-admit-current! observations "outer source changed")
                    (call-with-collected-module-sources
                      (lambda (inner)
                        (set! inner-current! inner)
                        (module-source-admit-current! observations "inner source changed"))))))))
          (outer-current!)
          (inner-current!)
          (write! "5440")
          ;; Equal-length replacement defeats a cardinality/length-only key.
          ;; Both owners must start independent, fresh return observations.
          (check-exception (outer-current!)
            (lambda (cause) (and (Error? cause) (string=? (Error-message cause) "outer source changed"))))
          (check-exception (inner-current!)
            (lambda (cause) (and (Error? cause) (string=? (Error-message cause) "inner source changed")))))))))
