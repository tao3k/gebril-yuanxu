;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Runtime cache boundaries, not a replacement module evaluator or build cache.
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
(export module-incremental-cache-test)
;; Standard with-slot-dependencies owns capture, issuance admission and weak edge
;; registration. This is a kernel control; automatic Loader enrollment remains
;; a separate source-correspondence and complete-CI gate.
(def module-incremental-cache-test
  (test-suite "Incremental runtime receiver and read-dependency boundaries"
    (yuanxu-test-case "one prototype edit leaves an unrelated receiver hot"
      (def affected-work 0)
      (def unrelated-work 0)
      (.def Base port: 5432)
      (.def (Service service [Base] port)
        plan: (begin (set! affected-work (1+ affected-work)) (list port)))
      (.def Unrelated
        plan: (begin (set! unrelated-work (1+ unrelated-work)) '(unchanged)))
      (def old (.get Service plan))
      (def untouched (.get Unrelated plan))
      (.putslot! Base 'port ($constant-slot-spec 5433))
      (check-equal? (.get Service plan) '(5433))
      (check-equal? (eq? untouched (.get Unrelated plan)) #t)
      (check-equal? affected-work 2)
      (check-equal? unrelated-work 1)
      (check-equal? old '(5432)))
    (yuanxu-test-case "a cross-object read does not promise automatic cache recomputation"
      (.def Provider port: 5432)
      (def computations 0)
      (.def Consumer
        plan: (begin (set! computations (1+ computations)) (list (.get Provider port))))
      (defvalues (old records)
        (%call-with-recorded-slot-reads (cut .get Consumer plan)))
      (check-equal? old '(5432))
      (check-equal? (pair? records) #t)
      (.put! Provider 'port 5433)
      ;; Runtime replay must refuse old dependency support. It must not silently
      ;; authorize the cached value as a fresh plan, even if .ref still hits it.
      (check-exception (replay-slot-reads! records void) error?)
      (check-equal? (.get Consumer plan) '(5432))
      (check-equal? computations 1)
      (displayln "INCREMENTAL-BOUNDARY prototype-recompute=2 unrelated=1 cross-read-stale-refused"))
    (yuanxu-test-case "runtime dependency enrollment recomputes a diamond exactly once"
      (.def Provider port: 5432)
      (def left-work 0)
      (def right-work 0)
      (def joined-work 0)
      (.def Left plan: (begin (set! left-work (1+ left-work)) (.get Provider port)))
      (.def Right plan: (begin (set! right-work (1+ right-work)) (.get Provider port)))
      (.def Joined plan: (begin (set! joined-work (1+ joined-work))
                          (list (.get Left plan) (.get Right plan))))
      ;; Actual public MOP operation. This is an explicit kernel control, not
      ;; proof that Loader already extracts/enrolls arbitrary module read edges.
      (depend-on-object! Left Provider)
      (depend-on-object! Right Provider)
      (depend-on-object! Joined Left)
      (depend-on-object! Joined Right)
      (defvalues (old records) (%call-with-recorded-slot-reads (cut .get Joined plan)))
      (def generation (object-revision Joined))
      (check-equal? old '(5432 5432))
      (.put! Provider 'port 5433)
      (check-equal? (object-revision Joined) (1+ generation))
      (check-exception (replay-slot-reads! records void) error?)
      (check-equal? (.get Joined plan) '(5433 5433))
      (check-equal? (.get Joined plan) '(5433 5433))
      (check-equal? (list left-work right-work joined-work) '(2 2 2))
      (displayln "INCREMENTAL-DEPENDENCY diamond-invalidated-once hot-reuse=yes"))
    (yuanxu-test-case "actual issued edges enroll demanded dependent receivers"
      (.def Database port: 5432)
      (def client-work 0)
      (def plan-work 0)
      (def unrelated-work 0)
      (.def (Client client [])
        port: (with-slot-dependencies client
                (lambda () (set! client-work (1+ client-work)) (.get Database port))))
      (.def (Application application [])
        plan: (with-slot-dependencies application
                (lambda () (set! plan-work (1+ plan-work)) (list (.get Client port))))
        unselected: (error "unselected branch evaluated"))
      (.def Unrelated
        plan: (begin (set! unrelated-work (1+ unrelated-work)) '(unchanged)))
      (def hot (.get Unrelated plan))
      (defvalues (old reads) (%call-with-recorded-slot-reads (cut .get Application plan)))
      (.put! Database 'port 5433)
      (check-exception (replay-slot-reads! reads void) error?)
      (def fresh (.get Application plan))
      (check-equal? old '(5432))
      (check-equal? fresh '(5433))
      (check-equal? (.get Application plan) '(5433))
      (check-equal? (eq? hot (.get Unrelated plan)) #t)
      (check-equal? (list client-work plan-work unrelated-work) '(2 2 1))
      (check-equal? (.ref/cached Application 'unselected) #f)
      (displayln "INCREMENTAL-ISSUED old=5432 new=5433 affected=2 unrelated=1 unselected=cold"))
    (yuanxu-test-case "immutable child refinement does not replace a cached parent"
      (.def Parent port: 5432 plan: (list port))
      (def cached (.get Parent plan))
      (.def (Child @ Parent) port: 5433)
      (check-equal? (.get Child plan) '(5433))
      (check-equal? (eq? cached (.get Parent plan)) #t))))
