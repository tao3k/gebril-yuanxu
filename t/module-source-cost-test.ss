;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Matched runtime IO accounting control; not a timing acceptance gate.
(import :std/test
        (only-in :std/error Error? Error-message)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :tao3k/yuanxu/module-system/source/admission module-source-read module-source-observe
                 module-source-admit-current! call-with-collected-module-sources
                 current-module-source-observer call-with-module-source-read-cache
                 call-with-module-source-operation-measurement module-source-measure-operation)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
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
    (yuanxu-test-case "stage summaries have bounded keys and preserve owner scope counts"
      (def (record count accounting?)
        (call-with-module-source-operation-measurement
          (lambda ()
            (check-equal? (current-module-source-observer) #f)
            (let loop ((left count))
              (unless (zero? left)
                (let (path (string-append "interface-" (number->string left)))
                  (module-source-measure-operation (list 'reader-initialization path) void)
                  (module-source-measure-operation (list 'reader-initializer-body path) void))
                (loop (1- left))))
            (module-source-measure-operation '(scope-factory owner-a) void)
            (module-source-measure-operation '(scope-factory owner-b) void)
            'checked)
          accounting?: accounting?))
      (defvalues (small small-counts) (record 2 'stages))
      (defvalues (large large-counts) (record 64 'stages))
      (check-equal? small 'checked)
      (check-equal? large 'checked)
      ;; Allocation-invalid counters are conditional on VM sampling; compare
      ;; the stable metric key set rather than their presence or numeric cost.
      (def (stable-keys counts)
        (filter (lambda (key) (not (and (pair? key) (eq? (car key) 'accounting-invalid))))
                (hash-keys counts)))
      (check-equal? (length (stable-keys small-counts)) (length (stable-keys large-counts)))
      (check-equal? (hash-ref large-counts '(calls reader-initialization)) 64)
      (check-equal? (hash-ref large-counts '(calls reader-initializer-body)) 64)
      (check-equal? (hash-ref large-counts '(calls (scope-factory owner-a))) 1)
      (check-equal? (hash-ref large-counts '(calls (scope-factory owner-b))) 1)
      (check-equal? (hash-get large-counts '(calls (reader-initialization "interface-1"))) #f)
      (defvalues (counted counters) (record 64 #f))
      (check-equal? counted 'checked)
      (check-equal? (hash-ref counters '(calls (scope-factory owner-a))) 1)
      (check-equal? (hash-ref counters '(calls (scope-factory owner-b))) 1)
      (check-equal? (hash-get counters '(calls reader-initialization)) #f)
      (defvalues (_detailed detailed-counts) (record 2 #t))
      (check-equal? (hash-ref detailed-counts '(calls (reader-initialization "interface-1"))) 1)
      (def failure (gensym 'stage-accounting-failure))
      (check-exception
        (call-with-module-source-operation-measurement
          (lambda ()
            (module-source-measure-operation '(reader-initialization "failed")
              (cut raise failure))) accounting?: 'stages)
        (lambda (cause) (eq? cause failure))))
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
