;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real module qualifications share init selection and source guards; no executor.
(import :std/test :tao3k/yuanxu/syntax/path-slots
        (only-in :clan/poo/object .get .call .ref/cached)
        (only-in "../init.ss" tao3k/yuanxu.init.exports)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :tao3k/yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint
                 yuanxu-test-observe)
        (only-in :tao3k/yuanxu/observability/testing-fixture yuanxu-test-fixture with-yuanxu-fixture))
(export module-testing-isolation-test)
(.def Workspace
  .acquire: (lambda ()
              (let (root (make-temporary-file-name "module-qualifications-"))
                (create-directory root) root))
  .release: (lambda (root)
              (clear-temporary-file! root)
              (check-equal? (file-exists? root) #f)))
(def module-testing-isolation-test
  (test-suite "JsonSchema init-owned qualifications"
    (yuanxu-test-fixture "owner selection and publication share one bounded Case"
      (workspace Workspace)
      (yuanxu-test-checkpoint 'selection-start)
      (def json (.call (.get tao3k/yuanxu.init.exports tests) .select '(json-schema)))
      (def reads 0)
      (def previous-observer (current-module-source-observer))
      (def (observe key amount)
        (when (and (pair? key) (eq? (car key) 'file-read))
          (set! reads (+ reads 1)))
        (when previous-observer (previous-observer key amount)))
      (def all
        (parameterize ((current-module-source-observer observe))
          (.get tao3k/yuanxu.init.exports tests qualification)))
      (check-equal? reads 0)
      (check-equal? (.ref/cached all 'selected-graph) #f)
      (check-equal? (.ref/cached all 'execution) #f)
      (check-equal? (.ref/cached all 'spec) #f)
      (def json-tests
        (parameterize ((current-module-source-observer observe))
          (.get json qualification)))
      (check-equal? (eq? json-tests (.call all .select '(json-schema))) #t)
      (def selected (.call all .select '(json-schema)))
      (check-equal? (eq? selected (.call selected .select '(json-schema))) #t)
      (check-equal? (.get selected spec) (.get json-tests spec))
      (check-equal? (eq? (.get json-tests selected-graph) (.get selected selected-graph)) #t)
      (check-equal? (.get selected selected-graph module-order)
                    '(tao3k/yuanxu/modules/json-schema/interface
                      tao3k/yuanxu/scenarios/gitea-postgresql/postgresql/interface
                      tao3k/yuanxu/scenarios/gitea-postgresql/gitea/interface
                      tao3k/yuanxu/scenarios/gitea-postgresql/interface))
      (check-equal? (.ref/cached selected 'execution) #f)
      (yuanxu-test-checkpoint 'selection-verified)
      (check-equal? (.ref/cached all 'spec) #f)
      (check-equal? (.ref/cached (.get tao3k/yuanxu.init.exports Modules) 'json-schema) #f)
      (def source (.get selected source))
      (def guard (.get selected admit-current))
      (check-equal? (eq? guard (.get source admit-current)) #t)
      (for-each (lambda (name) (check-equal? (.slot? selected name) #f))
                '(.run .compile execution))
      (guard)
      ;; Qualification selection never runs a Suite or forces business scopes.
      (check-equal? (.ref/cached json 'integration) #f)
      (check-equal? (.ref/cached all 'spec) #f)
      (check-equal? (directory-files workspace) '())
      (check-equal? (.ref/cached json 'scope) #f))))
