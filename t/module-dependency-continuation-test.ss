;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (prefix-in (only-in :gerbil/runtime/mop slot-ref slot-set!) runtime.)
        (only-in :clan/poo/object .o .get .all-slots .putslot! $thunk-slot-spec object?
                 object-%reads object-%instance object-%all-slots object-read-issued?)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer slot-read-value)
        (only-in :clan/poo/mop Type.)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :tao3k/yuanxu/module-system/source/admission
                 module-source-read current-module-source-observer admit-module-value!)
        (only-in :tao3k/yuanxu/module-system/source/publication ModulePublicationContract
                 module-publication-contract-current? module-publication-dependency-projection
                 module-publication-recorded-dependencies)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file))
(export module-dependency-continuation-test)
(def module-dependency-continuation-test
  (test-suite "Runtime dependency continuation with the maintained publication producer"
    (yuanxu-test-case "dependency projection requires actual tokens and never forces a cold leaf"
      (def reads (make-hash-table-eq))
      (def roots '())
      (def (remember! read)
        (set! roots (cons read roots))
        (hash-put! reads read #t))
      (def calls 0)
      (def Scope (.cc Type. identity: 'test/scope .element?: object?))
      (def Requirement (.o module-id: (begin (set! calls (+ calls 1)) 'custom/other) contract: Scope))
      (def Publication
        (.o identity: 'custom/example features: (.o)
            core: (.o requires: (.o Shared: Requirement)
                      scope-contract: Scope link: (lambda (_bindings) (.o)))))
      (def evidence
        (call-with-slot-read-observer
          remember!
          (lambda () (admit-module-value! ModulePublicationContract Publication #f))))
      (def candidate (.get evidence candidate))
      (check-equal? calls 1)
      (check-equal? (module-publication-dependency-projection candidate (lambda (_read) #f)) #f)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) '(custom/other))
      (check-equal? (module-publication-recorded-dependencies candidate '()) #f)
      (check-equal? (module-publication-recorded-dependencies candidate roots) '(custom/other))
      ;; A candidate can retain the original token while its lookup route
      ;; changes. Neither the instance nor the read-table ref may run here.
      (for-each
        (lambda (table)
          (def original (runtime.slot-ref table 'ref))
          (def calls 0)
          (dynamic-wind
            (lambda ()
              (runtime.slot-set! table 'ref
                (lambda (self key fallback)
                  (set! calls (1+ calls))
                  (original self key fallback))))
            (lambda ()
              (def projected (module-publication-recorded-dependencies candidate roots))
              (check-equal? calls 0)
              (check-equal? projected #f))
            (lambda () (runtime.slot-set! table 'ref original))))
        (list (object-%instance candidate) (object-%reads candidate)))
      (check-equal? (module-publication-recorded-dependencies candidate roots) '(custom/other))
      (def requires (.get candidate core requires))
      (def names-read (hash-ref (object-%reads requires) '(names)))
      (check-equal? (eq? (slot-read-value names-read) (object-%all-slots requires)) #f)
      (def public-copy (.all-slots requires))
      (set-car! public-copy 'unrelated)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) '(custom/other))
      ;; The public read accessor returns an owned copy too. Editing it cannot
      ;; corrupt the issuer's snapshot or invalidate an otherwise current read.
      (def exported (slot-read-value names-read))
      (set-cdr! exported exported)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) '(custom/other))
      ;; A corrupt observed spine is not a directory and must terminate without
      ;; fetching a dependency. A NEW real producer query may issue a new token.
      (def snapshot (runtime.slot-ref names-read 'value))
      (set-cdr! snapshot snapshot)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) #f)
      (check-equal? (module-publication-recorded-dependencies candidate roots) #f)
      (call-with-slot-read-observer
        remember!
        (lambda () (admit-module-value! ModulePublicationContract candidate #f)))
      (check-equal? (eq? names-read (hash-ref (object-%reads requires) '(names))) #f)
      (check-equal? (object-read-issued? names-read) #f)
      (check-equal? (object-read-issued? (hash-ref (object-%reads requires) '(names))) #t)
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) '(custom/other))
      (check-equal? calls 1)
      (.putslot! Requirement 'module-id
        ($thunk-slot-spec (lambda () (set! calls (+ calls 1)) 'custom/replaced)))
      (check-equal? (module-publication-dependency-projection candidate
                      (lambda (read) (hash-key? reads read))) #f)
      (check-equal? (module-publication-recorded-dependencies candidate roots) #f)
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
              ;; Prove the runtime deferred route ran, rather than a fallback
              ;; refusing early because this test modified the shared Contract.
              (check-equal? (hash-ref counts 'publication-admitted 0) 0)
              ;; The mutation affects this candidate's OWN config. The local
              ;; return guard now refuses before the old next-location/Feature
              ;; boundary. Keep the same real refusal and no-callback marker;
              ;; require the exact earlier runtime stage, not any exception.
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
