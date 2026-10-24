;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence)
        (only-in :yuanxu/admission/source SourceAdmissionContract.)
        (only-in :yuanxu/configuration/diagnostics config-diagnostic-locator)
        (only-in :yuanxu/module-system/source/admission
                 call-with-module-source-read-cache module-source-read module-source-admit-current!)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture write-source)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export source-admission-test test-cleanup!)

;; Test-only instrumentation below the adapter in the native method chain.
;; Counting classification alone would not prove inherited .admit ran once.
(def (counted-contract calls)
  (def base
    (.o (:: @ YuanxuContract.)
      (.admit (inherited)
        (lambda (candidate context)
          (vector-set! calls 0 (+ 1 (vector-ref calls 0)))
          ((inherited) candidate context)))))
  (.o (:: @ [SourceAdmissionContract. base])
    identity: 'test/source-admission
    .classify:
    (lambda (candidate context)
      (yuanxu-classification-evidence identity candidate #t '() context))))

(def completed 0)
(def (test-cleanup!)
  (unless (= completed 6) (error "incomplete source admission controls" completed))
  (displayln "SOURCE-ADMISSION: 6 cases completed"))
(def source-admission-test
  (test-suite "Source-bound native Contract admission"
    (yuanxu-test-fixture "replaceable currentness callbacks cannot lend bytes across their effects"
      (fixture DirectoryFixture)
      (def path (path-expand "context.json" (.get fixture root)))
      (write-source path "{}")
      (def calls (vector 0))
      (def contract (counted-contract calls))
      ;; Deliberately effectful negative context. A method name does not certify
      ;; purity; record an input, then edit it before returning to the adapter.
      (def context
        (.o admit-current:
          (lambda ()
            (module-source-admit-current! (list (cons path "{}")) "test context source changed")
            (write-source path "{\"changed\":true}"))))
      (def failure (with-catch values (cut .call contract .admit (.o) context)))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "test context source changed")
      (check-equal? (vector-ref calls 0) 1)
      (set! completed (+ completed 1)))
    (yuanxu-test-case "inherited admission runs exactly once on each invocation"
      (def calls (vector 0))
      (def contract (counted-contract calls))
      (def candidate (.o port: 5432))
      (def first (.call contract .admit candidate #f))
      (check-equal? (vector-ref calls 0) 1)
      (check-equal? (.get first accepted?) #t)
      (check-equal? (eq? (.get first candidate) candidate) #t)
      (def second (.call contract .admit candidate #f))
      (check-equal? (vector-ref calls 0) 2)
      (check-equal? (.get second accepted?) #t)
      (check-equal? (eq? (.get second admission-contract) contract) #t)
      (set! completed (+ completed 1)))
    (yuanxu-test-case "preflight refusal never calls inherited admission"
      (def calls (vector 0))
      (def issue (.o kind: 'invalid-field path: '(port)))
      (def contract
        (.o (:: @ (counted-contract calls))
          .preflight: (lambda (_candidate _path) (list issue))))
      (def candidate (.o port: "invalid"))
      (def rejected (.call contract .admit candidate #f))
      (check-equal? (vector-ref calls 0) 0)
      (check-equal? (.get rejected accepted?) #f)
      (check-equal? (eq? (.get rejected candidate) candidate) #t)
      (check-equal? (eq? (car (.get rejected diagnostics)) issue) #t)
      (set! completed (+ completed 1)))
    (yuanxu-test-case "child obligation and receipt identity survive decoration"
      (def child-calls (vector 0))
      (def child (.o port: 5433))
      (def issue (.o kind: 'child-policy path: '(port)))
      (def child-contract
        (.o (:: @ (counted-contract child-calls))
          .obligations: (lambda (_candidate _context) (list issue))))
      (def root-calls (vector 0))
      (def root-contract
        (.o (:: @ (counted-contract root-calls))
          .locate-diagnostic: (config-diagnostic-locator (.o) '(config))
          responsibilities: (.o database: child-contract)))
      (def rejected (.call root-contract .admit (.o database: child) #f))
      (check-equal? (vector-ref root-calls 0) 1)
      (check-equal? (vector-ref child-calls 0) 1)
      (check-equal? (.get rejected accepted?) #f)
      (def receipt (car (.get rejected responsibility-evidence)))
      (check-equal? (eq? receipt (car (.get rejected diagnostics))) #t)
      (check-equal? (eq? (.get receipt candidate) child) #t)
      (check-equal? (eq? (.get receipt admission-contract) child-contract) #t)
      (check-equal? (eq? (car (.get receipt diagnostics)) issue) #t)
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "outer cached observations cannot hide a changed source at entry"
      (fixture DirectoryFixture)
      (def path (path-expand "input.json" (.get fixture root)))
      (write-source path "{}")
      (def calls (vector 0))
      (def contract
        (.o (:: @ (counted-contract calls)) source-inputs: (list (cons path "{}"))))
      (call-with-module-source-read-cache
        (lambda ()
          (check-equal? (module-source-read path) "{}")
          (write-source path "{\"changed\":true}")
          (def failure (with-catch values (lambda () (.call contract .admit (.o) #f))))
          (check-equal? (Error? failure) #t)
          (check-equal? (Error-message failure) "configuration source changed")
          (check-equal? (vector-ref calls 0) 0)))
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "post-admission checks bypass an outer cache after obligation mutation"
      (fixture DirectoryFixture)
      (def path (path-expand "input.json" (.get fixture root)))
      (write-source path "{}")
      (def calls (vector 0))
      (def contract
        (.o (:: @ (counted-contract calls))
          source-inputs: (list (cons path "{}"))
          .obligations:
          (lambda (_candidate _context)
            ;; Negative control only; normal obligations remain pure.
            (write-source path "{\"changed\":true}")
            '())))
      (call-with-module-source-read-cache
        (lambda ()
          (check-equal? (module-source-read path) "{}")
          (def failure (with-catch values (lambda () (.call contract .admit (.o) #f))))
          (check-equal? (Error? failure) #t)
          (check-equal? (Error-message failure) "configuration source changed")
          (check-equal? (vector-ref calls 0) 1)))
      (set! completed (+ completed 1)))))
