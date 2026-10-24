;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
        %deliver-slot-read slot-read-dependencies slot-read-receiver make-slot-read)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection
                 owned-read-value! owned-read-derived!)
        (only-in :yuanxu/poo-clos/objects clos-call-carrier-policy-guard)
        (only-in :yuanxu/poo-clos/types ClosInvocationFrame)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export issued-root-forwarding-test)
(def (issued-closure? roots)
  (def seen (make-hash-table-eq))
  (def (valid? read)
    (or (hash-key? seen read)
        (and (object-read-issued? read)
             (begin (hash-put! seen read #t)
                    (andmap valid? (slot-read-dependencies read))))))
  (andmap valid? roots))
(def issued-root-forwarding-test
  (test-suite "Core forwards native issuance without synthetic bundles"
    (yuanxu-test-case "real roots retain exact identities, parent revisions and lazy branches"
      (def policy (.o port: 5432 unused: (error "unused field forced")))
      (def saved '())
      (defvalues (value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (defvalues (answer actual)
                  (%call-with-recorded-slot-reads (lambda () (.get policy port))))
                (set! saved actual)
                ;; Nested collector does not deliver to its parent automatically.
                ;; Forward each ORIGINAL native token, never rebuild its checker.
                (for-each (lambda (r) (%deliver-slot-read r #f)) actual)
                answer)))))
      (check-equal? value 5432)
      (check-equal? (issued-closure? reads) #t)
      (check-equal? (and (memq (car saved) reads) #t) #t)
      (replay-slot-reads! reads (lambda (_receiver _key) (void)))
      (.put! policy 'port 5433)
      (check-exception (replay-slot-reads! reads (lambda (_r _k) (void))) Error?))
    (yuanxu-test-case "raw record remains refused before observer callbacks"
      (def calls 0)
      (def forged (make-slot-read (.o) 'bundle 0 #f #f '() (lambda (_r) #t)))
      (def failure (with-catch values
        (lambda () (replay-slot-reads! (list forged) (lambda (_r _k) (set! calls (+ calls 1)))))))
      (check-equal? (Error-message failure) "unissued slot dependency")
      (check-equal? calls 0))
    (yuanxu-test-case "owned derived values retain unread parent generation"
      (def base (.o port: 5432))
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (def child (owned-read-derived! (.o (:: @ base) local: #t)))
                (.get child local))))))
      (check-equal? (issued-closure? reads) #t)
      (.put! base 'other #t)
      (.put! base 'other #f)
      (check-exception (replay-slot-reads! reads (lambda (_r _k) (void))) Error?))
    (yuanxu-test-case "failed actions retain original exception and native dependencies"
      (def policy (.o port: 5432))
      (def original (with-catch values (lambda () (error "original action failure"))))
      (defvalues (failure reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (with-catch values
              (lambda ()
                (call-with-owned-read-projection '() (lambda () #t)
                  (lambda () (.get policy port) (raise original))))))))
      (check-equal? (eq? failure original) #t)
      (check-equal? (pair? reads) #t)
      (check-equal? (issued-closure? reads) #t)
      (.put! policy 'port 5440)
      (check-exception (replay-slot-reads! reads (lambda (_r _k) (void))) Error?))
    (yuanxu-test-case "carrier policy uses original native revision reads"
      (def guard (clos-call-carrier-policy-guard))
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda () (call-with-owned-read-projection '() guard (lambda () 'done)))))
      (check-equal? (pair? reads) #t)
      (check-equal? (issued-closure? reads) #t)
      (def proto (.get ClosInvocationFrame proto))
      (def kind (.get proto kind))
      (dynamic-wind
        (lambda () (.put! proto 'kind 'modified-policy))
        (lambda () (check-exception (replay-slot-reads! reads (lambda (_r _k) (void))) Error?))
        (lambda () (.put! proto 'kind kind))))))
