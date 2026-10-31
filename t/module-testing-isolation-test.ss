;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real module qualifications share init selection, guards and Ops execution.
(import :std/test :yuanxu/object-syntax/path-slots
        (only-in :clan/poo/object .get .call .ref/cached)
        (only-in "../init.ss" yuanxu.init.exports)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint
                 yuanxu-test-observe)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture with-yuanxu-fixture))
(export module-testing-isolation-test)
(.def Workspace
  .acquire: (lambda ()
              (let (root (make-temporary-file-name "module-qualifications-"))
                (create-directory root) root))
  .release: (lambda (root)
              ;; Preserve the existing Ops observation stream before removing
              ;; its fixture. A failed Case must not erase its last phase.
              (dynamic-wind void
                (lambda ()
                  (let (log (path-expand "harness.log" root))
                    (when (file-exists? log)
                      (display (call-with-input-file log read-all-as-string) (current-error-port))
                      (force-output (current-error-port)))))
                (lambda ()
                  (clear-temporary-file! root)
                  (check-equal? (file-exists? root) #f)))))
(def module-testing-isolation-test
  (test-suite "JsonSchema and Funflow init-owned qualifications"
    (yuanxu-test-fixture "multi-owner selection and publication share one bounded Case"
      (workspace Workspace)
      (yuanxu-test-checkpoint 'selection-start)
      (def json (.get yuanxu.init.exports Modules json-schema))
      (def flow (.get yuanxu.init.exports Modules funflow))
      (def unused (.get flow tests))
      (def reads 0)
      (def funflow-read? #f)
      (def previous-observer (current-module-source-observer))
      (def (observe key amount)
        (when (and (pair? key) (eq? (car key) 'file-read))
          (set! reads (+ reads 1))
          (let (name (path-strip-directory (caddr key)))
            (when (string=? name "funflow-job-test.ss") (set! funflow-read? #t))))
        (when previous-observer (previous-observer key amount)))
      (def all
        (parameterize ((current-module-source-observer observe))
          (.get yuanxu.init.exports tests qualification)))
      (check-equal? reads 0)
      (check-equal? (.ref/cached all 'selected-graph) #f)
      (check-equal? (.ref/cached all 'execution) #f)
      (check-equal? (.ref/cached all 'spec) #f)
      (check-equal? (.ref/cached (.get flow tests) 'qualification) #f)
      (def json-tests
        (parameterize ((current-module-source-observer observe))
          (.get json tests qualification)))
      (check-equal? funflow-read? #f)
      (check-equal? (eq? json-tests (.call all .select '(json-schema))) #t)
      (check-equal? (.ref/cached (.get flow tests) 'qualification) #f)
      (def flow-tests (.get flow tests qualification))
      (def selected (.call all .select '(json-schema funflow)))
      (check-equal? (eq? selected (.call selected .select '(json-schema funflow))) #t)
      (check-equal? (.get selected spec)
        (append (.get json-tests spec) (.get flow-tests spec)))
      (check-equal? (eq? (.get json-tests selected-graph) (.get selected selected-graph)) #t)
      (check-equal? (eq? (.get flow-tests selected-graph) (.get selected selected-graph)) #t)
      (check-equal? (.ref/cached unused 'integration) #f)
      (check-equal? (.get selected selected-graph module-order)
                    '(json-schema funflow services/postgresql services/gitea applications/gitea-postgresql))
      (check-equal? (.ref/cached selected 'execution) #f)
      (yuanxu-test-checkpoint 'selection-verified)
      (check-equal? (.ref/cached all 'spec) #f)
      (for-each (lambda (module) (check-equal? (.ref/cached module 'scope) #f))
        (list json flow))
      (check-equal?
        (eq? selected (.call all .select '(json-schema funflow))) #t)
      (def source (.get selected source))
      (def guard (.get selected admit-current))
      ;; xcrun's actual cache database must not occupy source-reader scratch.
      ;; Reuse the SAME Fixture; no shared host cache or ignored residue.
      (with-yuanxu-fixture (tool-cache Workspace)
        (.def (Run @ selected)
          ;; Observation belongs to this init-owned test object. Ops propagates
          ;; the selected policy to child fixtures; no author-side Profile.
          execution.profile.emit?: #t
          execution.profile.trace-enabled?: #t
          execution.environment.TMPDIR: workspace
          execution.environment.xcrun_db: (path-expand "xcrun_db" tool-cache)
          execution.log: (path-expand "harness.log" workspace))
        (check-equal? (.get Run execution profile emit?) #t)
        (check-equal? (.get Run execution profile trace-enabled?) #t)
        (check-equal? (eq? (.get Run execution source) source) #t)
        (check-equal? (eq? (.get Run admit-current) guard) #t)
        (yuanxu-test-checkpoint 'qualification-run)
        (def receipt (.call Run .run))
        (yuanxu-test-observe 'test-worker-milliseconds
          (inexact->exact (round (* 1000 (.get receipt seconds)))))
        (yuanxu-test-checkpoint 'qualification-complete)
        (check-equal? (directory-files workspace) '("harness.log"))
        ;; The unselected integration branch stays cold during qualification.
        (check-equal? (.ref/cached (.get flow tests) 'integration) #f)
        (check-equal? (.ref/cached all 'spec) #f)
        (for-each (lambda (module) (check-equal? (.ref/cached module 'scope) #f))
          (list (.get yuanxu.init.exports Modules json-schema)
                (.get yuanxu.init.exports Modules funflow)))))
    (test-case "Ops failure unwinds the existing fixture"
      (def acquired #f)
      (check-exception
        (with-yuanxu-fixture (workspace Workspace)
          (set! acquired workspace)
          (.def (Failed @ (.get yuanxu.init.exports Modules funflow tests qualification))
            execution.command: '("false")
            execution.environment.TMPDIR: workspace)
          (.call Failed .run)) error?)
      (check-equal? (file-exists? acquired) #f))))
