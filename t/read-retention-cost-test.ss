;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Structural cost receipt, not a timing or retained-heap acceptance threshold.
(import :std/test :clan/poo/object
        (only-in :std/error Error?)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
                 call-with-slot-read-observer slot-read-dependencies slot-read-receiver slot-read-key)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/debug yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/funcs yuanxu-debug-allocation-current?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures ServicesFixture))
(export read-retention-cost-test test-cleanup!)
(def completed 0)
(def allocation-stream-current? #t)
(def allocation-previous #f)
(def (test-cleanup!)
  (unless (= completed 12) (error "retention measurements incomplete" completed))
  (displayln "READ-RETENTION: 3 raw/unique cold/warm rounds completed"))

(def (read-graph observed-roots)
  (def seen (make-hash-table-eq))
  (def root-set (make-hash-table-eq))
  (def owners (make-hash-table-eq))
  (def edge-count 0)
  (def miss-count 0)
  (def (visit read)
    (unless (hash-key? seen read)
      (check-equal? (object-read-issued? read) #t)
      (hash-put! seen read #t)
      (hash-put! owners (slot-read-receiver read) #t)
      (let ((key (slot-read-key read)) (edges (slot-read-dependencies read)))
        (when (and (pair? key) (eq? (car key) 'cache-miss))
          (set! miss-count (+ miss-count 1)))
        (set! edge-count (+ edge-count (length edges)))
        (for-each visit edges))))
  (for-each (lambda (read) (hash-put! root-set read #t) (visit read)) observed-roots)
  (.o deliveries: (length observed-roots)
      roots: (hash-length root-set)
      records: (hash-length seen)
      receivers: (hash-length owners)
      edges: edge-count
      misses: miss-count))

(def (check-final evidence cached parent)
  (check-equal? (.get evidence accepted?) #t)
  (def final (.get evidence candidate))
  (check-equal? (.get final plan postgresql port) 5433)
  (check-equal? (.get final plan gitea database-port) 5433)
  (check-equal? (eq? (.get final config) (.get final plan configuration)) #t)
  (check-equal? (.get cached postgresql port) 5432)
  (check-equal? (eq? cached (.get parent plan)) #t)
  (def configuration (car (.get evidence responsibility-evidence)))
  (check-equal? (eq? (.get configuration candidate) (.get final config)) #t)
  (check-equal? (length (.get configuration responsibility-evidence)) 2))

(def (measure round mode child contract context cached parent unique?)
  (def physical-reads 0)
  (def observer-keys '())
  (def before (yuanxu-debug-memory-snapshot 'retention-before))
  (when allocation-previous
    (set! allocation-stream-current?
      (yuanxu-debug-allocation-current? allocation-stream-current?
        allocation-previous (.ref before 'allocated-bytes))))
  (def started (real-time))
  (defvalues (evidence reads)
    (call-with-slot-read-observer
      (lambda (read) (set! observer-keys (cons (slot-read-key read) observer-keys)))
      (lambda ()
        (%call-with-recorded-slot-reads
          (lambda ()
            (parameterize ((current-module-source-observer
                            (lambda (key amount)
                              (when (and (pair? key) (eq? (car key) 'file-read))
                                (set! physical-reads (+ physical-reads amount))))))
              (.call contract .admit child context)))
          unique-roots?: unique?))))
  (def seconds (- (real-time) started))
  (def after (yuanxu-debug-memory-snapshot 'retention-after))
  (set! allocation-stream-current?
    (yuanxu-debug-allocation-current? allocation-stream-current?
      (.ref before 'allocated-bytes) (.ref after 'allocated-bytes)))
  (set! allocation-previous (.ref after 'allocated-bytes))
  (check-final evidence cached parent)
  (def graph (read-graph reads))
  (check-equal? (> (.get graph records) 0) #t)
  (check-equal? (> (.get graph records) (.get graph receivers)) #t)
  (check-equal? (length (.get context contributions)) 2)
  (when unique? (check-equal? (.get graph deliveries) (.get graph roots)))
  (write (list 'READ-RETENTION round mode
    'collection (if unique? 'unique 'raw) 'observer-calls (length observer-keys)
    'seconds seconds 'file-reads physical-reads
    'allocation-current? allocation-stream-current? 'raw-allocation-delta
    (- (.ref after 'allocated-bytes) (.ref before 'allocated-bytes))
    'deliveries (.get graph deliveries) 'roots (.get graph roots)
    'records (.get graph records) 'receivers (.get graph receivers)
    'edges (.get graph edges) 'misses (.get graph misses)))
  (newline)
  (set! completed (+ completed 1))
  (reverse observer-keys))

(def read-retention-cost-test
  (test-suite "Real Scenario demanded read-graph cost"
    (yuanxu-test-case "distinct native misses remain outside the read cache"
      (.def Policy port: 5432 unused: (error "unselected slot forced"))
      (defvalues (_answer reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (.ref/cached Policy 'missing (lambda () #f))
            (.ref/cached Policy 'missing (lambda () #f)))))
      (def graph (read-graph reads))
      (check-equal? (.get graph misses) 2)
      (check-equal? (hash-get (object-%reads Policy) '(cache-miss missing)) #f)
      (replay-slot-reads! reads (lambda (_receiver _key) (void)))
      (.put! Policy 'missing #t)
      (check-exception (replay-slot-reads! reads (lambda (_r _k) (void))) Error?))
    (yuanxu-test-fixture "three matched cold and warm admissions keep exact child semantics"
      (fixture ServicesFixture)
      (with-slots (publication selection) fixture
        (def parent (.get publication value))
        (def cached (.get parent plan))
        (def contract (.get publication contract))
        (def context (.get publication context))
        (check-equal? (memq 'services/unused (.get selection selected-graph module-order)) #f)
        ;; Share descriptor/catalog initialization, not a child value or an
        ;; approval. Every measured admission still owns fresh source checks.
        (check-equal? (.get (.call contract .admit parent context) accepted?) #t)
        (for-each
          (lambda (round)
            ;; Cold is a fresh child receiver, not a cold process or cold OS cache.
            (.def (Raw @ parent)
              config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
            (.def (Release @ parent)
              config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
            (def (sample mode unique?)
              (measure round mode (if unique? Release Raw) contract context cached parent unique?))
            (def unique-first? (even? round))
            (def cold (sample 'cold unique-first?))
            (check-equal? (sample 'cold (not unique-first?)) cold)
            (def warm (sample 'warm unique-first?))
            (check-equal? (sample 'warm (not unique-first?)) warm))
          '(1 2 3))))))
