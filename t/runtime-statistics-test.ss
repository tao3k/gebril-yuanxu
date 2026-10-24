;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Installed-runtime accounting controls; no forced collection or RTS edits.
(import :std/test
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/admission
                 call-with-module-source-operation-measurement module-source-measure-operation))
(export runtime-statistics-test)

(def (retained-pairs count)
  (let loop ((remaining count) (result '()))
    (if (zero? remaining) result
      (loop (- remaining 1) (cons remaining result)))))

(def runtime-statistics-test
  (test-suite "installed Gambit accounting semantics"
    (yuanxu-test-case "native exec-stats reports accounting rather than constructor bytes"
      (for-each
        (lambda (count)
          (let* ((stats (##exec-stats (lambda () (retained-pairs count))))
                 (result (cdr (assq 'result stats))))
            (check-equal? (length result) count)
            (for-each
              (lambda (key) (check-equal? (number? (cdr (assq key stats))) #t))
              '(user-time sys-time real-time gc-user-time gc-sys-time gc-real-time nb-gcs bytes-allocated))
            (displayln "RUNTIME-ACCOUNTING pairs=" count " metrics="
              (filter (lambda (entry) (not (eq? (car entry) 'result))) stats))))
        '(0 1000 10000 1000))
      (defvalues (results times)
        (call-with-module-source-operation-measurement
          (lambda ()
            (call-with-values
              (lambda () (module-source-measure-operation 'metadata-replay
                            (lambda () (values 'left 'right)))) list))))
      (check-equal? results '(left right))
      (check-equal? (hash-ref times '(calls metadata-replay)) 1)
      (def failure (cons 'original 'error))
      (defvalues (caught failed-times)
        (call-with-module-source-operation-measurement
          (lambda ()
            (with-catch (lambda (exception) (eq? exception failure))
              (lambda ()
                (module-source-measure-operation 'metadata-replay (lambda () (raise failure))))))))
      (check-equal? caught #t)
      (check-equal? (hash-ref failed-times '(calls metadata-replay)) 1))))
