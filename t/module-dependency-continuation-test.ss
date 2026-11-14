;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :tao3k/yuanxu/module-system/source/admission
                 module-source-read current-module-source-observer)
        (only-in :tao3k/yuanxu/module-system/source/publication module-publication-contract-current?)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in "./qualification/module-publication/fixtures.ss"
                 with-publication-source write-file exception-message))
(export module-dependency-continuation-test)
(def module-dependency-continuation-test
  (test-suite "Runtime dependency continuation with the maintained publication producer"
    (yuanxu-test-case "pending source changes refuse before a declaration or Feature callback"
      (for-each
        (lambda (boundary)
          (with-publication-source
            (lambda (root module-root _source _view)
              (check-equal? (module-publication-contract-current?) #t)
              (def marker (path-expand "must-not-execute" root))
              (write-file (path-expand "init.ss" root)
                (if (eq? boundary 'declaration)
                  "(yuanxu! :test-dir \"./t\" mode: explicit :custom (example) (other))"
                  "(yuanxu! :test-dir \"./t\" mode: explicit :custom (example +ci))"))
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
                         core: (.o scope-contract: FixtureContract exports: FixtureScope)
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
                  "(.def Fixture identity: 'custom/other core: (.o scope-contract: FixtureContract exports: FixtureScope) features: (.o))")))
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
    (yuanxu-test-case "a source edit during contract lookup refuses before demanding an imported owner's scope"
      (with-publication-source
        (lambda (root module-root _source _view)
          (check-equal? (module-publication-contract-current?) #t)
          (def marker (path-expand "cold-dependency-must-not-run" root))
          (def provider (path-expand "modules/custom/other" root))
          (def config (path-expand "config.ss" module-root))
          (write-file (path-expand "init.ss" root)
            "(yuanxu! :test-dir \"./t\" mode: explicit :custom (example) (other))")
          (write-file (path-expand "types.ss" provider)
            "(def ProviderValue 'provider) (export ProviderValue)")
          (write-file (path-expand "interface.ss" provider)
            (object->string
              `(.def Provider identity: 'custom/other
                core: (.o scope-contract: (error "provider scope contract demanded")
                          exports: (begin
                            (call-with-output-file ,marker
                              (lambda (out) (display "unexpected" out)))
                            (.o)))
                features: (.o))))
          (write-file (path-expand "interface.ss" module-root)
            (call-with-output-string
              (lambda (port)
                (write '(import (only-in "../other/types.ss" ProviderValue)) port)
                (newline port)
                (write
                  `(.def Fixture identity: 'custom/example
                     core: (.o scope-contract:
                       (begin
                         (unless (eq? ProviderValue 'provider)
                           (error "wrong imported owner"))
                         (call-with-output-file
                           (list path: ,config truncate: #t)
                           (lambda (out) (display "(def Changed #t) (export Changed)" out)))
                         FixtureContract)
                       exports: FixtureScope)
                     features: (.o)) port))))
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def refusal (exception-message (lambda () (.get view selected-graph))))
          (check-equal? (and (string-contains refusal "stale") #t) #t)
          (check-equal? (and (string-contains (module-source-read config) "def Changed") #t) #t)
          (check-equal? (file-exists? marker) #f)
          (check-equal? (module-publication-contract-current?) #t))))))
