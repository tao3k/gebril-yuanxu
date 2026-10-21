;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Copied unchanged to a generated Module test directory by the Core fixture.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in "../../../init.ss" init.modules init.tests)
        (only-in :core/observability/memory poo-flow-debug-memory-snapshot)
        (only-in :core/observability/output poo-flow-write-observation-line!)
        (only-in :core/module-system/source/admission current-module-source-observer module-source-read)
        (only-in :core/observability/testing-case
                 poo-flow-test-case poo-flow-test-checkpoint))
(export worker-test)
(def worker-test
  (test-suite "Real native declaration expansion through init"
    (poo-flow-test-case "all selected declarations expand without linking business scopes"
      (def count (length (.all-slots init.modules)))
      (def counts (make-hash-table-eq))
      (def class-construction-reads 0)
      (def previous (current-module-source-observer))
      (def (observe key amount)
        (def category (if (pair? key) (car key) key))
        (when (and (eq? category 'file-read)
                   (string-suffix? "/poo-clos/classes.ss" (caddr key)))
          (set! class-construction-reads (+ class-construction-reads amount)))
        ;; This fixture imports only the maintained SDK and its own roles.
        ;; Fail at an unexpected fallback rather than spending the full
        ;; thousand-entry budget proving the same wrong import classification.
        (when (eq? category 'candidate-open-boundary)
          (error "closed native declaration crossed an unexpected open boundary" (cdr key)))
        (when (memq category '(publication-start publication-discovered candidate-local-guard candidate-open-guard
                              reader-declaration reader-body-expanded reader-body-evaluated
                              native-source-import-start publication-guard-run file-read))
          (hash-update! counts category (cut + <> amount) 0))
        (when previous (previous key amount)))
      (poo-flow-test-checkpoint 'native-graph-start)
      (def graph
        (parameterize ((current-module-source-observer observe))
          (.get init.tests selected-graph)))
      (poo-flow-test-checkpoint 'native-graph-ready)
      (check-equal? (eq? graph (.get init.tests selected-graph)) #t)
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
      (check-equal? (.ref/cached (.get init.modules module-0) 'scope) #f)
      ;; The delegated observer already recorded these events. Replaying the
      ;; assertion counters would double the published work totals.
      ;; The path is supplied by the actual Graph, never a guessed fixture root.
      (def path (.get graph init-source))
      (def original (module-source-read path))
      (def current! (.get graph admit-current))
      ;; Measure the normal live Graph. GC is an Observability measurement,
      ;; not cache invalidation: the same selected Graph remains reachable.
      (def held (poo-flow-debug-memory-snapshot 'graph-held collect?: #t))
      (poo-flow-write-observation-line!
        "reader-graph-live modules=%s live-bytes=%s" count (.get held live-bytes))
      (check-equal? (eq? graph (.get init.tests selected-graph)) #t)
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
