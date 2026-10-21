;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolation controls: runtime metadata setters are not POO object edits.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop call-with-slot-read-observer replay-slot-reads! slot-read-key)
        (prefix-in (only-in :gerbil/runtime/mop slot-ref slot-set!) runtime.)
        (only-in :gerbil/runtime/table &raw-table-hash &raw-table-hash-set!
                 &raw-table-test &raw-table-test-set! &raw-table-seed &raw-table-seed-set!)
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export mop-route-mutation-test test-cleanup!)
(def completed 0)
(def (port-read receiver)
  (def result #f)
  (call-with-slot-read-observer
    (lambda (read) (when (eq? (slot-read-key read) 'port) (set! result read)))
    (cut .get receiver port))
  result)
(def (refuses message action)
  (def failure (with-catch values action))
  (check-equal? (Error? failure) #t)
  (check-equal? (Error-message failure) message))
;; Private fixture combinator; it calls the real setter and restores on failure.
(def (change-and-restore get put next)
  (def saved (get))
  (dynamic-wind
    (lambda () (put next))
    (lambda () (check-equal? (eq? (get) next) #t))
    (lambda () (put saved))))
(def mop-route-mutation-test
 (test-suite "Metadata write ownership and restoration boundary"
  (yuanxu-test-case "active computation rejects supported receiver writes before mutation"
    (def read #f)
    (.def Root port: 5432
      audit: (begin (replay-slot-reads! (list read)
                       (lambda (_owner key) (when (eq? key 'port) (.put! Root 'port 5440)))) #t)
      unused: (error "unselected branch forced"))
    (set! read (port-read Root))
    (def revision (object-revision Root))
    (refuses "object mutation during computation" (cut .get Root audit))
    (check-equal? (object-revision Root) revision)
    (check-equal? (object-read-current? read) #t)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "sealed receiver and active frame do not track raw metadata restoration"
    (def read #f)
    (def changes 0)
    (def calls 0)
    (.def Root port: 5432
      audit:
      (begin
        (replay-slot-reads! (list read)
          (lambda (_owner key)
            (when (eq? key 'port)
              (for-each
                (lambda (table)
                  (def original (runtime.slot-ref table 'ref))
                  (dynamic-wind
                    (lambda () (runtime.slot-set! table 'ref
                      (lambda (self key default)
                        (set! calls (+ calls 1)) (original self key default))))
                    (lambda () (hash-ref table 'port #f))
                    (lambda () (runtime.slot-set! table 'ref original)))
                  (def backend (runtime.slot-ref table 'object))
                  (change-and-restore (cut runtime.slot-ref table 'object)
                    (cut runtime.slot-set! table 'object <>)
                    (runtime.slot-ref (make-hash-table) 'object))
                  (change-and-restore (cut &raw-table-hash backend)
                    (cut &raw-table-hash-set! backend <>) (lambda (_key) 0))
                  (change-and-restore (cut &raw-table-test backend)
                    (cut &raw-table-test-set! backend <>) (lambda (_a _b) #t))
                  (change-and-restore (cut &raw-table-seed backend)
                    (cut &raw-table-seed-set! backend <>) (+ 1 (&raw-table-seed backend)))
                  (set! changes (+ changes 5)))
                (list (object-%reads Root) (object-%instance Root))))))
        #t)
      unused: (error "unselected branch forced"))
    (set! read (port-read Root))
    (def revision (object-revision Root))
    (seal-object! Root)
    (check-equal? (.get Root audit) #t)
    (check-equal? changes 10)
    (check-equal? calls 2)
    (check-equal? (object-revision Root) revision)
    (check-equal? (object-read-current? read) #t)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "unrestored route refuses before invoking the foreign method"
    (.def Root port: 5432)
    (def read (port-read Root))
    (def table (object-%reads Root))
    (def original (runtime.slot-ref table 'ref))
    (def calls 0)
    (dynamic-wind
      (lambda () (runtime.slot-set! table 'ref
        (lambda (_self _key _default) (set! calls (+ calls 1)) read)))
      (lambda () (refuses "changed metadata ref"
        (cut replay-slot-reads! (list read) (lambda (_owner _key) #t))))
      (lambda () (runtime.slot-set! table 'ref original)))
    (check-equal? calls 0)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "parent cached reads remain separate from final child reads"
    (.def Parent port: 5432 unused: (error "unselected branch forced"))
    (def parent-read (port-read Parent))
    (.def (Child @ Parent) port: 5433)
    (def child-read (port-read Child))
    (check-equal? (eq? parent-read child-read) #f)
    (replay-slot-reads! (list child-read) (lambda (_owner _key) #t))
    (check-equal? (.get Parent port) 5432)
    (check-equal? (.get Child port) 5433)
    (check-equal? (object-read-current? parent-read) #t)
    (check-equal? (object-read-current? child-read) #t)
    (set! completed (+ completed 1)))))
(def (test-cleanup!)
  (check-equal? completed 4)
  (displayln "ROUTE-MUTATION: 4 cases; 10 restored metadata writes; 2 actual callback calls"))
