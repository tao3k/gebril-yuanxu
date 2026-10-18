;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Opt-in matched native IO allocation control; not a timing acceptance gate.
(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :core/module-system/source/admission module-source-read
                 current-module-source-observer call-with-module-source-read-cache)
        (only-in :core/observability/debug poo-flow-debug-memory-snapshot)
        (only-in :core/observability/testing-case poo-flow-test-case))
(export module-source-cost-test)
(def module-source-cost-test
  (test-suite "Source guard allocation"
    (poo-flow-test-case "same real source snapshot and independent fresh reads"
      (displayln "SOURCE-RUNTIME max-heap=" (##get-max-heap))
      (check-equal? (> (##get-max-heap) 0) #t)
      (def expected
        (module-source-read
          (path-expand "../module-system/source/reader.ss" (path-directory (this-source-file)))))
      (call-with-temporary-directory "source-read-allocation"
        (lambda (root)
          (def file (path-expand "reader.ss" root))
          (call-with-output-file file (cut display expected <>))
          (def (checks)
            (let loop ((left 200))
              (unless (zero? left)
                (unless (equal? expected (module-source-read file))
                  (error "changed source during matched read control"))
                (loop (- left 1)))))
          (def (measure name work expected-reads)
            (def reads 0)
            (def before (poo-flow-debug-memory-snapshot name collect?: #t))
            (def started (real-time))
            (parameterize ((current-module-source-observer
                            (lambda (key amount)
                              (when (eq? key 'reads) (set! reads (+ reads amount))))))
              (work))
            (def seconds (- (real-time) started))
            (def after (poo-flow-debug-memory-snapshot name collect?: #t))
            (def allocation (- (.ref after 'allocated-bytes) (.ref before 'allocated-bytes)))
            (check-equal? reads expected-reads)
            (check-equal? (> allocation 0) #t)
            (displayln "SOURCE-ALLOCATION " name " reads=" reads " characters=" (string-length expected)
                       " allocated=" allocation " seconds=" seconds))
          (measure 'independent checks 200)
          (measure 'pure-window (lambda () (call-with-module-source-read-cache checks)) 1))))))
