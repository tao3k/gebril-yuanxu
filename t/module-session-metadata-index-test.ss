;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in "./module-candidate-stage-test" with-other-source)
        (only-in "./qualification/module-publication/fixtures.ss" write-file)
        (only-in :tao3k/yuanxu/module-system/source/admission
                 call-with-module-source-operation-measurement current-module-source-observer
                 module-source-measure-replay)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads)
        (only-in :tao3k/yuanxu/module-system/source/reader-support
                 merge-publication-root-segments publication-read-current)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
(export module-session-metadata-index-test)
(def (checked-work view (accounting? #t))
  (check-equal? (current-module-source-observer) #f)
  (defvalues (_ times)
    (call-with-module-source-operation-measurement (.get view admit-current) accounting?: accounting?))
  ;; A fixed number of standard replay invocations, not a claim of constant-time
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
  (test-suite "Standard POO session metadata topology and fresh authentication"
    (yuanxu-test-case "the session root union retains standard traversal and refusal order"
      (def first (.o left: 1))
      (def second (.o right: 2))
      (defvalues (_left left) (%call-with-recorded-slot-reads (lambda () (.ref first 'left))))
      (defvalues (_right right) (%call-with-recorded-slot-reads (lambda () (.ref second 'right))))
      ;; Ten thousand rows exercise the production aggregation without
      ;; re-expanding ten thousand native Interfaces in this focused Case.
      (def rows (cons (cons left (append left right))
                      (cons #f (make-list 9998 (cons right left)))))
      (def original (append left left right right left))
      (def projected (merge-publication-root-segments rows values))
      (check-equal? (< (length projected) (length original)) #t)
      (def (trace roots)
        (def events '())
        (replay-slot-reads! roots
          (lambda (receiver key) (set! events (cons (cons receiver key) events))))
        (reverse events))
      (check-equal? (trace projected) (trace original))
      (.put! first 'left 3)
      (.put! second 'right 4)
      (def (refusal roots)
        (with-catch
          (lambda (cause) (cons (Error-message cause) (Error-irritants cause)))
          (lambda () (module-source-measure-replay roots) #f)))
      (check-equal? (refusal projected) (refusal original))
      (check-equal? (car (refusal projected)) "stale slot dependency"))
    (yuanxu-test-case "checkpoint runs once under standard protection and retains its failure"
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
      (check-exception (module-source-measure-replay reads) error?)
      (check-exception (module-source-measure-replay reads (lambda () (set! calls (1+ calls)))) error?)
      (check-equal? calls 1))
    (yuanxu-test-case "validation-only replay authenticates the same issued traversal"
      (def receivers (map (lambda (index) (.o field: index)) (iota 256)))
      (defvalues (_ reads)
        (%call-with-recorded-slot-reads
          (lambda () (for-each (lambda (receiver) (.ref receiver 'field)) receivers))
          unique-roots?: #t))
      (def (visitor-count)
        (def visits 0)
        (replay-slot-reads! reads (lambda (_receiver _key) (set! visits (1+ visits))))
        visits)
      (def expected (visitor-count))
      (check-equal? (call-with-current-slot-reads reads values) expected)
      (def (sample action)
        (def stats (##exec-stats action))
        (check-equal? (cdr (assq 'result stats)) expected)
        (map (lambda (key) (cdr (assq key stats))) '(user-time sys-time real-time)))
      (def visitor '(0. 0. 0.))
      (def checkpoint '(0. 0. 0.))
      (def (visit!) (set! visitor (map + visitor (sample visitor-count))))
      (def (verify!)
        (set! checkpoint
          (map + checkpoint (sample (lambda () (call-with-current-slot-reads reads values))))))
      (for-each (lambda (index) (if (even? index) (begin (visit!) (verify!)) (begin (verify!) (visit!))))
                (iota 24))
      (displayln "METADATA-CHECKPOINT-COST visits=" expected " samples=24 user/sys/wall"
        " visitor=" visitor " checkpoint=" checkpoint)
      (defvalues (_result times)
        (call-with-module-source-operation-measurement (lambda () (module-source-measure-replay reads))))
      (check-equal? (hash-ref times '(visits metadata-replay)) expected)
      (check-equal? (hash-get times '(calls metadata-checkpoints)) #f)
      (def (observer-events visits)
        (list (cons '(metadata-replay-start runtime) 1)
              (cons 'metadata-replay-visits visits)
              (cons '(metadata-replay-end runtime) 1)))
      (def (observe-guard start)
        (def events '())
        (defvalues (failure accounting)
          (call-with-module-source-operation-measurement
            (lambda ()
              (with-catch values
                (lambda ()
                  (parameterize ((current-module-source-observer
                                   (lambda (key amount)
                                     (set! events (cons (cons key amount) events))
                                     (when (equal? key '(metadata-replay-start runtime))
                                       (start)))))
                    ((publication-read-current reads)))
                  #f)))
            accounting?: 'stages))
        (check-equal? (hash-ref accounting '(calls observed-metadata-replay)) 1)
        (values failure (reverse events)))
      (defvalues (success events) (observe-guard void))
      (check-equal? success #f)
      (check-equal? events (observer-events expected))
      (defvalues (refusal rejected-events)
        (observe-guard
          (lambda ()
            (.put! (cadr receivers) 'field -1)
            (current-module-source-observer #f))))
      (def prefix-visits 0)
      (def original
        (with-catch values
          (lambda ()
            (replay-slot-reads! reads
              (lambda (_receiver _key) (set! prefix-visits (1+ prefix-visits)))))))
      (check-equal? (> prefix-visits 0) #t)
      (check-equal? (< prefix-visits expected) #t)
      (check-equal? (Error-message refusal) (Error-message original))
      (check-equal? (Error-irritants refusal) (Error-irritants original))
      (check-equal? rejected-events (observer-events prefix-visits)))
    (yuanxu-test-case "each observed publication rechecks shared reads after its start event"
      (def receiver (.o field: 1))
      (defvalues (_ reads) (%call-with-recorded-slot-reads (lambda () (.ref receiver 'field))))
      (def first (publication-read-current reads))
      (def second (publication-read-current reads))
      (def starts 0)
      (def visits '())
      (parameterize ((current-module-source-observer
                       (lambda (key amount)
                         (cond
                          ((equal? key '(metadata-replay-start runtime))
                           (set! starts (1+ starts))
                           (when (= starts 2) (.put! receiver 'field 2)))
                          ((eq? key 'metadata-replay-visits)
                           (set! visits (cons amount visits)))))))
        (first)
        (check-exception (second)
          (lambda (cause)
            (and (Error? cause) (equal? (Error-message cause) "stale slot dependency")))))
      (check-equal? starts 2)
      (check-equal? (length visits) 2)
      (check-equal? (> (cadr visits) (car visits)) #t))
    (yuanxu-test-case "actual source growth invalidates topology; restored values remain stale"
      (with-other-source
        (lambda (root _first _other)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! :test-dir \"./t\" source: \"./modules\" mode: explicit :custom (example) (other))"))
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
          ;; A separate leaf demand appends an actual standard publication to
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
            "(yuanxu! :test-dir \"./t\" source: \"./modules\" mode: explicit :custom (example) (other))"))
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
