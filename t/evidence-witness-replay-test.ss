;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads replay-slot-reads!
                 slot-read-key slot-read-receiver slot-read-dependencies)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection owned-read-leaf!)
        (only-in :yuanxu/object-types/contracts yuanxu-classification-evidence yuanxu-validation-evidence)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export evidence-witness-replay-test)
(def (has-full-bundle? reads)
  (def seen (make-hash-table-eq))
  (def (visit read)
    (and (not (hash-key? seen read))
      (begin (hash-put! seen read #t)
        (or (eq? (slot-read-key read) 'owned-call/full)
            (ormap visit (slot-read-dependencies read))))))
  (if (ormap visit reads) #t #f))
(def (retained-receiver-path reads weak name)
  ;; Diagnostic values are slot labels only, never tokens or receivers.
  (def seen (make-hash-table-eq))
  (def (visit read path)
    (and (not (hash-key? seen read))
      (begin
        (hash-put! seen read #t)
        (let* ((key (slot-read-key read))
               (next (cons (if (symbol? key) key 'structural) path)))
          (if (eq? (slot-read-receiver read) (hash-get weak name)) (reverse next)
            (ormap (cut visit <> next) (slot-read-dependencies read)))))))
  (ormap (cut visit <> '()) reads))
(def evidence-witness-replay-test
  (test-suite "Native live-witness replay boundaries"
    (yuanxu-test-case "shared witness suffix is replayed once per closed native batch"
      ;; A read-only counter is a cost probe, not a production validator.
      ;; The owned receivers stay strongly reachable in the returned value;
      ;; collecting them must not be what makes the probe cheaper.
      (def (work count)
        (def visits 0)
        (def shared (.o answer: #t))
        (defvalues (held reads)
          (%call-with-recorded-slot-reads
            (lambda ()
              (call-with-owned-read-projection '() (lambda () #t)
                (lambda ()
                  (map (lambda (_index)
                         ;; Test-only stand-in for an audited Core factory.
                         (def value
                           (owned-read-leaf! (.o answer: (.get shared answer))))
                         (.get value answer)
                         value)
                    (iota count)))))))
        (set! visits 0)
        (check-equal? (has-full-bundle? reads) #f)
        (replay-slot-reads! reads
          (lambda (receiver key)
            (when (and (eq? receiver shared) (eq? key 'answer))
              (set! visits (+ visits 1)))))
        (check-equal? (length held) count)
        ;; Record cost before the negative: a refusal may stop at a different
        ;; hash iteration point, which is not a successful replay work count.
        (def successful visits)
        ;; A returned live witness still rejects a native mutation.
        (.put! (car held) 'answer #f)
        (check-exception (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?)
        successful)
      (def one (work 1))
      (check-equal? (> one 0) #t)
      (check-equal? (work 4) one)
      (check-equal? (work 8) one))
    (yuanxu-test-case "original witness tokens pin receivers during replay-time GC"
      (def weak (make-hash-table-eq weak-values: #t))
      (def until-replay (box '()))
      (def armed? #f)
      (def collected? #f)
      (def shared (.o identity: 'fixture))
      (def contract (.o identity: (.get shared identity)))
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (for-each
                  (lambda (name)
                    (def value
                      (yuanxu-validation-evidence contract #t
                        (yuanxu-classification-evidence 'fixture #t #t '() #f)
                        '() #t '() #f))
                    (hash-put! weak name value)
                    (set-box! until-replay (cons value (unbox until-replay)))
                    (.get value contract-identity)) '(first second))
                #t)))))
      ;; The callback drops the fixture's last strong references before GC.
      (check-equal? (has-full-bundle? reads) #f)
      (set! armed? #t)
      (replay-slot-reads! reads
        (lambda (receiver key)
          (when (and (eq? receiver shared) (eq? key 'identity)
                     armed? (not collected?))
            (set! collected? #t)
            (set-box! until-replay '())
            (yuanxu-debug-memory-snapshot 'issued-roots-held collect?: #t)
            (check-equal? (object? (hash-get weak 'first)) #t)
            (check-equal? (object? (hash-get weak 'second)) #t))))
      (check-equal? collected? #t)
      (yuanxu-write-observation-line! "witness-strong-path first=%s second=%s"
        (retained-receiver-path reads weak 'first)
        (retained-receiver-path reads weak 'second))
      ;; The original issued graph owns its receivers until it is released.
      (yuanxu-debug-memory-snapshot 'issued-graph-retained collect?: #t)
      (check-equal? (object? (hash-get weak 'first)) #t)
      (check-equal? (object? (hash-get weak 'second)) #t)
      (set! reads '())
      (yuanxu-debug-memory-snapshot 'witness-roots-released collect?: #t)
      (check-equal? (hash-get weak 'first) #f)
      (check-equal? (hash-get weak 'second) #f))))
