;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in "./module-candidate-stage-test" with-other-source)
        (only-in "./qualification/module-publication/fixtures.ss" write-file)
        (only-in :yuanxu/module-system/source/admission
                 call-with-module-source-operation-measurement current-module-source-observer
                 module-source-measure-replay)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-session-metadata-index-test)
(def (checked-work view (accounting? #t))
  (check-equal? (current-module-source-observer) #f)
  (defvalues (_ times)
    (call-with-module-source-operation-measurement (.get view admit-current) accounting?: accounting?))
  ;; A fixed number of native replay invocations, not a claim of constant-time
  ;; source/receiver authentication. Visits must still cover actual support.
  (check-equal? (hash-ref times '(calls metadata-replay)) 1)
  (check-equal? (hash-ref times '(calls metadata-checkpoints)) 1)
  (check-equal? (> (hash-ref times '(visits metadata-replay)) 0) #t)
  ;; Attribution observes the real replay and never installs source callbacks
  ;; or a second per-file timing frame. Zero reads is valid for a replay that
  ;; only authenticates receiver metadata; absence of the span is not.
  (check-equal? (hash-key? times '(read-attempts metadata-replay)) #t)
  (check-equal? (hash-key? times '(read-attempts source-read)) #f)
  (check-equal? (hash-key? times '(cpu-user metadata-replay)) accounting?)
  times)
(def module-session-metadata-index-test
  (test-suite "Native POO session metadata topology and fresh authentication"
    (yuanxu-test-case "checkpoint runs once under native protection and retains its failure"
      (def value (.o field: 1))
      (defvalues (_ reads) (%call-with-recorded-slot-reads (lambda () (.get value field))))
      (def calls 0)
      (module-source-measure-replay reads (lambda () (set! calls (1+ calls))))
      (check-equal? calls 1)
      (check-exception
        (module-source-measure-replay reads (lambda () (.put! value 'field 2))) error?)
      (check-equal? (.get value field) 1)
      (def failure (gensym 'checkpoint-failure))
      (check-equal? (eq? failure
        (with-catch values
          (lambda () (module-source-measure-replay reads (lambda () (raise failure)))))) #t)
      (.put! value 'field 2)
      (.put! value 'field 1)
      (check-exception (module-source-measure-replay reads (lambda () (set! calls (1+ calls)))) error?)
      (check-equal? calls 1))
    (yuanxu-test-case "actual source growth invalidates topology; restored values remain stale"
      (with-other-source
        (lambda (root _first _other)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! source: \"./modules\" mode: auto :custom (example))"))
        (lambda (_root _first _other view)
          (def modules (.get view modules custom))
          (check-equal? (.ref/cached modules 'example) #f)
          (check-equal? (.get modules example greeting) "hello")
          (check-equal? (.ref/cached modules 'other) #f)
          (def before (checked-work view))
          ;; Build-style scalar timing still authenticates the complete support.
          ;; It must not turn every source read into a VM/GC accounting sample.
          (def scalar (checked-work view #f))
          (check-equal? (hash-key? scalar '(cpu-user source-read)) #f)
          (check-equal? (hash-ref scalar '(calls metadata-replay))
                        (hash-ref before '(calls metadata-replay)))
          ;; A separate auto demand appends an actual native publication to
          ;; the SAME session, rather than reconstructing a second loader.
          (check-equal? (.get modules other greeting) "hello")
          (def after (checked-work view))
          (check-equal? (> (hash-ref after '(visits metadata-replay))
                           (hash-ref before '(visits metadata-replay))) #t)
          (def graph (.get view selected-graph))
          (def publication (.get (car (.get graph nodes)) publication))
          (def identity (.get publication identity))
          (.put! publication 'identity 'changed)
          (check-exception ((.get view admit-current)) error?)
          (.put! publication 'identity identity)
          ;; Topology membership is unchanged, but the original issued token's
          ;; receiver revision changed twice. No previous approval is reusable.
          (check-exception ((.get view admit-current)) error?))))
    (yuanxu-test-case "source observers retain original split checks and cold scopes"
      (with-other-source
        (lambda (root _first _other)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! source: \"./modules\" mode: explicit :custom (example) (other))"))
        (lambda (_root _first _other view)
          (def graph (.get view selected-graph))
          (check-equal? (length (.get graph module-order)) 2)
          (checked-work view)
          (def callbacks 0)
          (parameterize ((current-module-source-observer
                           (lambda (_key _amount) (set! callbacks (1+ callbacks)))))
            ((.get view admit-current)))
          (check-equal? (> callbacks 0) #t)
          (check-equal? (.ref/cached (.get view modules custom) 'example) #f)
          (check-equal? (.ref/cached (.get view modules custom) 'other) #f)
          (check-equal? (eq? graph (.get view selected-graph)) #t))))))
