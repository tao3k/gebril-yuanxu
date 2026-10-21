;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (prefix-in (only-in :gerbil/runtime/mop slot-ref slot-set!) runtime.)
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        "qualification/mop-state/metadata-ownership")
(export mop-metadata-ownership-test test-cleanup!)
(def completed 0)
(def (record action)
  (def roots '())
  (call-with-slot-read-observer (lambda (read) (set! roots (cons read roots))) action)
  (reverse roots))
(def (refuses message action)
  (def failure (with-catch values action))
  (check-equal? (Error? failure) #t)
  (check-equal? (Error-message failure) message))
(def mop-metadata-ownership-test
 (test-suite "Owned metadata gateway and retained raw bypasses"
  (yuanxu-test-case "genuine read associations reject replacement before restoration or effects"
    (.def Root port: 5432 unused: (error "unselected branch forced"))
    (def roots (record (cut .get Root port)))
    (def reads (object-%reads Root))
    (def instance (object-%instance Root))
    (def writes 0)
    (for-each
      (lambda (entry)
        (def target (car entry))
        (def field (cdr entry))
        (def original (runtime.slot-ref target field))
        (def replacement
          (if (procedure? original)
            (lambda args (set! writes (+ writes 1)) (apply original args))
            original))
        (refuses "object mutation during read replay"
          (cut call-with-owned-metadata roots
            (lambda (_owner _key)
              (metadata-set! target field replacement)
              (set! writes (+ writes 1))
              (metadata-set! target field original))))
        (check-equal? (eq? (runtime.slot-ref target field) original) #t))
      (list (cons Root '%reads) (cons reads 'ref) (cons instance 'ref)
            (cons reads 'object)
            (cons (object-%state Root) 'revision)
            (cons (car roots) 'current?)))
    (check-equal? writes 0)
    (refuses "object mutation during read replay"
      (cut call-with-owned-metadata roots
        (lambda (_owner _key)
          (metadata-set! (runtime.slot-ref reads 'object) 'hash values))))
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "unknown metadata cannot self-assign ownership"
    (.def Root port: 5432)
    (def unknown (make-hash-table))
    (refuses "unowned metadata write"
      (cut call-with-owned-metadata (record (cut .get Root port))
        (lambda (_owner _key) (metadata-set! unknown 'ref values))))
    (set! completed (+ completed 1)))
  (yuanxu-test-case "nested ownership retains outer receiver and exceptions unwind"
    (.def Outer port: 5432)
    (.def Inner port: 5433)
    (def roots (record (cut .get Outer port)))
    (def problem (with-catch values (lambda () (error "sentinel"))))
    (call-with-owned-metadata roots
      (lambda (_owner _key)
        (refuses "object mutation during read replay"
          (cut call-with-owned-metadata (record (cut .get Inner port))
            (lambda (_owner _key)
              (metadata-set! (object-%reads Outer) 'ref values))))
        (check-equal?
          (eq? problem (with-catch values
            (cut call-with-owned-metadata (record (cut .get Inner port))
              (lambda (_owner _key) (raise problem))))) #t)))
    (refuses "unowned metadata write"
      (cut metadata-set! (object-%reads Outer) 'ref values))
    (.put! Outer 'port 5440)
    (check-equal? (.get Outer port) 5440)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "transient miss is owned without inserting a cached read"
    (.def Root port: 5432 unused: (error "unselected branch forced"))
    (.get Root port)
    (def roots (record (cut .ref/cached Root 'missing (lambda () #f))))
    (refuses "object mutation during read replay"
      (cut call-with-owned-metadata roots
        (lambda (_owner _key) (metadata-set! (car roots) 'current? values))))
    (check-equal? (hash-key? (object-%reads Root) '(cache-miss missing)) #f)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "exported generated setter still bypasses a library gateway"
    (.def Root port: 5432)
    (def roots (record (cut .get Root port)))
    (def original (object-%reads Root))
    (def calls 0)
    (call-with-owned-metadata roots
      (lambda (_owner _key)
        (object-%reads-set! Root (make-hash-table))
        (set! calls (+ calls 1))
        (object-%reads-set! Root original)))
    (check-equal? (> calls 0) #t)
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "SDK reflective setter still invokes a replacement before restoring it"
    (.def Root port: 5432)
    (def roots (record (cut .get Root port)))
    (def table (object-%reads Root))
    (def original (runtime.slot-ref table 'ref))
    (def calls 0)
    (call-with-owned-metadata roots
      (lambda (_owner _key)
        (dynamic-wind
          (lambda () (runtime.slot-set! table 'ref
            (lambda (self key default)
              (set! calls (+ calls 1)) (original self key default))))
          (lambda () (hash-get table 'port))
          (lambda () (runtime.slot-set! table 'ref original)))))
    (check-equal? (> calls 0) #t)
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))))
(def (test-cleanup!)
  (check-equal? completed 6)
  (displayln "METADATA-OWNERSHIP: 6 cases; generated and reflective bypasses retained"))
