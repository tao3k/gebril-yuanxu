;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .get .putslot! $thunk-slot-spec object?)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/admission
                 module-source-read current-module-source-observer admit-module-value!)
        (only-in :yuanxu/module-system/source/publication ModulePublicationContract
                 module-publication-contract-current? module-publication-dependency-projection)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file))
(export module-dependency-continuation-test)
(def module-dependency-continuation-test
  (test-suite "Native dependency continuation with the maintained publication producer"
    (yuanxu-test-case "dependency projection requires actual tokens and never forces a cold leaf"
      (def reads (make-hash-table-eq))
      (def calls 0)
      (def Scope (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '())))
      (def Requirement (.o module-id: (begin (set! calls (+ calls 1)) 'custom/other) contract: Scope))
      (def Publication
        (.o identity: 'custom/example features: (.o)
            core: (.o requires: (.o Shared: Requirement)
                      scope-contract: Scope link: (lambda (_bindings) (.o)))))
      (def evidence
        (call-with-slot-read-observer
          (lambda (read) (hash-put! reads read #t))
          (lambda () (admit-module-value! ModulePublicationContract Publication #f))))
      (def candidate (.get evidence candidate))
      (check-equal? calls 1)
      (check-equal? (module-publication-dependency-projection candidate (lambda (_read) #f)) #f)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) '(custom/other))
      (.putslot! Requirement 'module-id
        ($thunk-slot-spec (lambda () (set! calls (+ calls 1)) 'custom/replaced)))
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) #f)
      (check-equal? calls 1))
    (yuanxu-test-case "pending source changes refuse before a declaration or Feature callback"
      (for-each
        (lambda (boundary)
          (with-publication-source
            (lambda (root module-root _source _view)
              (check-equal? (module-publication-contract-current?) #t)
              (def marker (path-expand "must-not-execute" root))
              (write-file (path-expand "init.ss" root)
                (if (eq? boundary 'declaration)
                  "(yuanxu! mode: explicit :custom (example) (other))"
                  "(yuanxu! mode: explicit :custom (example +ci))"))
              (write-file (path-expand "interface.ss" module-root)
                (call-with-output-string
                  (lambda (port)
                    (write
                      `(.def Fixture
                         identity: (begin
                           (call-with-output-file
                             (list path: ,(path-expand "config.ss" module-root) truncate: #t)
                             (lambda (out) (display "(def Greeting \"changed during admission\") (export Greeting)" out)))
                           'custom/example)
                         core: (.o requires: (.o) scope-contract: FixtureContract exports: FixtureScope)
                         features:
                         ,(if (eq? boundary 'declaration) '(.o)
                            `(.o ci: (begin
                               (call-with-output-file ,marker
                                 (lambda (out) (display "unexpected" out)))
                               (error "Feature executed before source refusal"))))) port))))
              (when (eq? boundary 'declaration)
                (let (other (path-expand "modules/custom/other" root))
                (for-each
                  (lambda (role)
                    (write-file (path-expand role other)
                      (module-source-read (path-expand role module-root))))
                  '("types.ss" "objects.ss"))
                (write-file (path-expand "config.ss" other)
                  (string-append "(call-with-output-file " (object->string marker)
                    " (lambda (out) (display \"unexpected\" out))) (def Greeting \"other\") (export Greeting)"))
                (write-file (path-expand "interface.ss" other)
                  "(.def Fixture identity: 'custom/other core: (.o requires: (.o) scope-contract: FixtureContract exports: FixtureScope) features: (.o))")))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (def counts (make-hash-table-eq))
              (def previous (current-module-source-observer))
              (parameterize
                  ((current-module-source-observer
                     (lambda (key amount)
                       (when (and (pair? key) (eq? (car key) 'publication-guard-start))
                         (hash-update! counts (cadr key) (cut + <> amount) 0))
                       (when previous (previous key amount)))))
                (check-exception (.get view selected-graph) error?))
              (check-equal? (file-exists? marker) #f)
              ;; Prove the native deferred route ran, rather than a fallback
              ;; refusing early because this test modified the shared Contract.
              (check-equal? (hash-ref counts 'publication-admitted 0) 0)
              ;; The mutation affects this candidate's OWN config. The local
              ;; return guard now refuses before the old next-location/Feature
              ;; boundary. Keep the same real refusal and no-callback marker;
              ;; require the exact earlier native stage, not any exception.
              (check-equal? (> (hash-ref counts 'candidate-admitted 0) 0) #t)
              (check-equal? (module-publication-contract-current?) #t))))
        '(declaration feature)))
    (yuanxu-test-case "a new cold dependency after shape checking retains the full return guard"
      (with-publication-source
        (lambda (root module-root _source _view)
          (check-equal? (module-publication-contract-current?) #t)
          (def marker (path-expand "cold-dependency-must-not-run" root))
          (write-file (path-expand "init.ss" root)
            "(yuanxu! mode: explicit :custom (example))")
          (write-file (path-expand "config.ss" module-root)
            "(import (only-in :clan/poo/object .o .putslot! $thunk-slot-spec) \"./types.ss\") (def PendingRequirement (.o module-id: 'custom/other contract: FixtureContract)) (export PendingRequirement)")
          ;; scope-contract is read AFTER the predicate checks requires. This
          ;; mutates a separate child receiver, not the actively computing Core.
          (write-file (path-expand "interface.ss" module-root)
            (call-with-output-string
              (lambda (port)
                (write
                  `(.def Fixture identity: 'custom/example
                     core:
                     (.o requires: (.o First: PendingRequirement)
                       scope-contract:
                       (begin
                         (.putslot! PendingRequirement 'module-id
                           ($thunk-slot-spec
                             (lambda ()
                               (call-with-output-file ,marker
                                 (lambda (out) (display "unexpected" out)))
                               'custom/other)))
                         (call-with-output-file
                           (list path: ,(path-expand "config.ss" module-root) truncate: #t)
                           (lambda (out) (display "(def Changed #t) (export Changed)" out)))
                         FixtureContract)
                       exports: FixtureScope)
                     features: (.o)) port))))
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (check-exception (.get view selected-graph) error?)
          (check-equal? (file-exists? marker) #f)
          (check-equal? (module-publication-contract-current?) #t))))))
