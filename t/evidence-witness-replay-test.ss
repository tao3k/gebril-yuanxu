;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads replay-slot-reads!
                 slot-read-key slot-read-receiver slot-read-dependencies make-slot-read %deliver-slot-read)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection owned-read-leaf!)
        (only-in :yuanxu/types yuanxu-classification-evidence yuanxu-validation-evidence)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export evidence-witness-replay-test)
;; Synthetic cost/GC tokens must have the same prepared receiver invariant as
;; a real native slot delivery. A cold synthetic receiver correctly opens the
;; whole region and therefore cannot test weak-witness collection.
(def (replay-probe-read key current?)
  (def receiver (.o))
  (.all-slots receiver)
  (make-slot-read receiver key 0 #f #f '() current?))
(def (has-full-bundle? reads)
  (def seen (make-hash-table-eq))
  (def (visit read)
    (and (not (hash-key? seen read))
      (begin (hash-put! seen read #t)
        (or (eq? (slot-read-key read) 'owned-call/full)
            (ormap visit (slot-read-dependencies read))))))
  (if (ormap visit reads) #t #f))
;; Keep this fixture formula outside the Case frame. It may capture the probe
;; token, never a receiver returned later by a production evidence factory.
(def (replay-probe-contract read)
  (.o identity: (%deliver-slot-read read 'fixture)))
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
        (def shared
          (replay-probe-read 'shared-suffix
            (lambda (_read) (set! visits (+ visits 1)) #t)))
        (defvalues (held reads)
          (%call-with-recorded-slot-reads
            (lambda ()
              (call-with-owned-read-projection '() (lambda () #t)
                (lambda ()
                  (map (lambda (_index)
                         ;; Test-only stand-in for an audited Core factory.
                         (def value
                           (owned-read-leaf! (.o answer: (%deliver-slot-read shared #t))))
                         (.get value answer)
                         value)
                    (iota count)))))))
        (set! visits 0)
        (check-equal? (has-full-bundle? reads) #f)
        (replay-slot-reads! reads (lambda (_receiver _key) (void)))
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
      (def shared
        (replay-probe-read 'gc-during-replay
          (lambda (_read)
            (when (and armed? (not collected?))
              (set! collected? #t)
              ;; Release the fixture's strong references only AFTER the native
              ;; batch has resolved its roots, then collect inside that replay.
              (set-box! until-replay '())
              (yuanxu-debug-memory-snapshot 'native-witness-roots-held collect?: #t)
              (check-equal? (object? (hash-get weak 'first)) #t)
              (check-equal? (object? (hash-get weak 'second)) #t))
            #t)))
      (def contract (replay-probe-contract shared))
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
      (replay-slot-reads! reads (lambda (_receiver _key) (void)))
      (check-equal? collected? #t)
      (yuanxu-write-observation-line! "witness-strong-path first=%s second=%s"
        (retained-receiver-path reads weak 'first)
        (retained-receiver-path reads weak 'second))
      (yuanxu-debug-memory-snapshot 'witness-roots-released collect?: #t)
      (check-equal? (hash-get weak 'first) #f)
      (check-equal? (hash-get weak 'second) #f))))
