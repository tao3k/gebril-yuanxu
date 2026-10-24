;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Copied unchanged to a generated Module test directory by the Core fixture.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/t/qualification/module-init/fixture import-fixture-init!)
        (only-in :yuanxu/t/qualification/module-scale/fixture declaration-scale-profile)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer module-source-read)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-test-case/with
                 yuanxu-test-checkpoint))
(def FixtureExports
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (import-fixture-init! (path-expand "../../../init.ss" (path-directory (this-source-file))))))
(export worker-test)
(def worker-test
  (test-suite "Real native declaration expansion through init"
    (yuanxu-test-case/with
      (declaration-scale-profile (length (.all-slots (.get FixtureExports modules))))
      "all selected declarations expand without linking business scopes"
      (def count (length (.all-slots (.get FixtureExports modules))))
      (def counts (make-hash-table-eq))
      (def class-construction-reads 0)
      (def completed-declarations 0)
      (def previous (current-module-source-observer))
      (def (observe key amount)
        (def category (if (pair? key) (car key) key))
        (when (and (eq? category 'file-read)
                   (string-suffix? "/poo-clos/classes.ss" (caddr key)))
          (set! class-construction-reads (+ class-construction-reads amount)))
        ;; This fixture imports only the maintained SDK and its own roles.
        ;; Fail at an unexpected fallback rather than spending the full
        ;; thousand-entry budget proving the same wrong import classification.
        ;; A warm known import need not import new code. Completion of an
        ;; actual declaration still advances the Case's scalar progress frame.
        ;; Do not construct typed checkpoint receipts inside an active reader.
        (when (eq? category 'publication-end)
          (set! completed-declarations (+ completed-declarations amount))
          (execution-progress! '(declaration-completed) completed-declarations)
          ;; Scalar snapshots follow real completed publications, not a timer.
          ;; Do not force GC or construct POO diagnostics inside this observer.
          (when (zero? (modulo completed-declarations 100))
            (let (stats (##process-statistics))
              (displayln "DECLARATION-MEMORY completed=" completed-declarations
                         " heap=" (f64vector-ref stats 15)
                         " live=" (f64vector-ref stats 17)
                         " allocated=" (f64vector-ref stats 7))
              (force-output))))
        (when (eq? category 'candidate-open-boundary)
          ;; Scalar-only failure attribution: constructing a typed receipt here
          ;; would reenter the admission whose refusal we are diagnosing.
          (let (stats (##process-statistics))
            (displayln "DECLARATION-REFUSAL heap=" (f64vector-ref stats 15)
                       " live=" (f64vector-ref stats 17)
                       " allocated=" (f64vector-ref stats 7))
            (force-output))
          (error "closed native declaration crossed an unexpected open boundary" (cdr key)))
        (when (memq category '(publication-start publication-discovered candidate-local-guard candidate-open-guard
                              reader-declaration reader-body-expanded reader-body-evaluated
                              native-source-import-start publication-guard-run file-read))
          (hash-update! counts category (cut + <> amount) 0))
        (when previous (previous key amount)))
      (yuanxu-test-checkpoint 'native-graph-start)
      (def graph
        (parameterize ((current-module-source-observer observe))
          (.get FixtureExports tests selected-graph)))
      (yuanxu-test-checkpoint 'native-graph-ready)
      (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
      (check-equal? (length (.get graph module-order)) count)
      (check-equal? (car (.get graph module-order)) 'module-0)
      (check-equal? (hash-ref counts 'publication-start) count)
      (check-equal? (hash-ref counts 'publication-discovered) count)
      (check-equal? (hash-ref counts 'candidate-local-guard) (* 4 count))
      (check-equal? (hash-get counts 'candidate-open-guard) #f)
      ;; Prototype-only dispatch queries descriptor values; it must not import
      ;; or register the optional logical Class construction implementation.
      (check-equal? class-construction-reads 0)
      ;; Each interface reports expanded/compiled/evaluated snapshots; the
      ;; three role bodies plus interface each expand and evaluate once.
      (check-equal? (hash-ref counts 'reader-declaration) (* 3 count))
      (check-equal? (hash-ref counts 'reader-body-expanded) (* 4 count))
      (check-equal? (hash-ref counts 'reader-body-evaluated) (* 4 count))
      (check-equal? (.ref/cached (.get FixtureExports modules module-0) 'scope) #f)
      ;; The delegated observer already recorded these events. Replaying the
      ;; assertion counters would double the published work totals.
      ;; The path is supplied by the actual Graph, never a guessed fixture root.
      (def path (.get graph init-source))
      (def original (module-source-read path))
      (def current! (.get graph admit-current))
      ;; Measure the normal live Graph. GC is an Observability measurement,
      ;; not cache invalidation: the same selected Graph remains reachable.
      (def held (yuanxu-debug-memory-snapshot 'graph-held collect?: #t))
      (yuanxu-write-observation-line!
        "reader-graph-live modules=%s live-bytes=%s" count (.get held live-bytes))
      (check-equal? (eq? graph (.get FixtureExports tests selected-graph)) #t)
      (dynamic-wind
        (lambda ()
          (call-with-output-file (list path: path truncate: #t)
            (lambda (port) (display original port) (newline port))))
        (lambda ()
          (check-exception (current!)
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception) "stale module scope generation")))))
        (lambda ()
          (call-with-output-file (list path: path truncate: #t) (cut display original <>)))))))
