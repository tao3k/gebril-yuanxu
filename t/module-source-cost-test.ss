;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Matched native IO accounting control; not a timing acceptance gate.
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-observe
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
          (check-equal? queries 2))))))
