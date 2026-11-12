;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        :tao3k/yuanxu/module-system/catalog/metadata
        (only-in :std/error Error? Error-message)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))

(export metadata-capacity-test)

(def (name index) (string->symbol (string-append ":catalog/module-" (number->string index))))
(def (version index) (string->symbol (string-append "v" (number->string index))))

(def (measure size shape stage action)
  (def result #f)
  (def stats (##exec-stats (lambda () (set! result (action)))))
  (def (metric key) (cdr (assq key stats)))
  (write (list 'catalog-capacity size shape stage
               'wall (metric 'real-time)
               'cpu (+ (metric 'user-time) (metric 'sys-time))
               'gc-cpu (+ (metric 'gc-user-time) (metric 'gc-sys-time))
               'collections (metric 'nb-gcs)))
  (newline)
  (force-output)
  result)

(def (exercise size shape hub-count)
  (def next-index 0)
  (def end-reads 0)
  (def name-count (- size hub-count))
  (def hub ':catalog/hub)
  (def selected-name (name (quotient name-count 2)))
  (def untouched-name (name 0))
  (def (timed stage action) (measure size shape stage action))
  (def snapshot
    (timed 'cold-build
      (lambda ()
        (module-metadata-catalog
          (lambda ()
            (if (= next-index size)
              (begin (set! end-reads (+ end-reads 1)) #!eof)
              (let (index next-index)
                (set! next-index (+ next-index 1))
                (if (< index name-count)
                  (module-catalog-release (name index) 'v1 'leaf-deps)
                  (module-catalog-release hub (version (- index name-count)) 'hub-deps)))))))))
  (check-equal? next-index size)
  (check-equal? end-reads 1)
  (def selected
    (timed 'first-resolution
      (lambda () (module-metadata-resolve snapshot selected-name 'v1))))
  (timed 'warm-10000-resolutions
    (lambda ()
      (let loop ((remaining 10000))
        (unless (zero? remaining)
          (unless (eq? selected (module-metadata-resolve snapshot selected-name 'v1))
            (error "unstable catalog resolution" selected-name))
          (loop (- remaining 1))))))
  (let (listed (timed 'hub-versions (lambda () (module-metadata-versions snapshot hub))))
    (check-equal? (length listed) hub-count)
    (check-equal? (car listed) 'v0))
  (def dependency-reads 0)
  (def (read-dependencies actual version ref)
    (set! dependency-reads (+ dependency-reads 1))
    (list actual version ref))
  (check-equal? (timed 'dependency-demand
                  (lambda () (module-metadata-dependencies snapshot selected read-dependencies)))
                (list selected-name 'v1 'leaf-deps))
  (def new-hub-release (module-catalog-release hub 'new 'new-deps))
  (def retained-hub-release (module-metadata-resolve snapshot hub (version (- hub-count 1))))
  (def updated
    (timed 'two-edits
      (lambda ()
        (module-metadata-publish snapshot
          (list (module-catalog-edit selected #f)
                (module-catalog-edit #f new-hub-release))))))
  (check-equal? (module-metadata-resolve updated selected-name 'v1) #f)
  (check-equal? (module-metadata-versions updated untouched-name)
                (module-metadata-versions snapshot untouched-name))
  (check-eq? (module-metadata-resolve updated untouched-name 'v1)
             (module-metadata-resolve snapshot untouched-name 'v1))
  (check-eq? (module-metadata-resolve updated hub 'new) new-hub-release)
  (check-eq? (module-metadata-resolve snapshot hub 'new) #f)
  (check-eq? (module-metadata-resolve updated hub (version (- hub-count 1))) retained-hub-release)
  (check-exception (module-metadata-dependencies updated selected read-dependencies)
    (lambda (failure)
      (and (Error? failure) (equal? (Error-message failure) "stale catalog release"))))
  (def conflict
    (timed 'conflict-after-edit
      (lambda ()
        (with-catch values
          (lambda ()
            (module-metadata-publish snapshot
              (list (module-catalog-edit selected #f)
                    (module-catalog-edit selected
                      (module-catalog-release selected-name 'v1 'new-deps)))))))))
  (check (and (Error? conflict) (equal? (Error-message conflict) "catalog version conflict")) => #t)
  (check-equal? (eq? (module-metadata-resolve snapshot selected-name 'v1) selected) #t)
  (check-equal? dependency-reads 1)
  (write (list 'catalog-work size shape 'producer-rows next-index 'version-labels hub-count
               'dependency-reads dependency-reads 'edits 2 'conflicts 1))
  (newline))

(def (exercise-shapes size)
  (exercise size 'wide 128)
  (exercise size 'skewed (quotient size 2)))

(def metadata-capacity-test
  (test-suite "Independent metadata catalog capacity"
    (yuanxu-test-case "100,000 releases with wide and skewed version indexes" (exercise-shapes 100000))
    (yuanxu-test-case "1,000,000 releases with wide and skewed version indexes" (exercise-shapes 1000000))))
