;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation shared by publication suites; no test suite is imported.
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/source this-source-file)
        (only-in :std/list/list find)
        (only-in :std/error Error? Error-message)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :gerbil/runtime/loader load-path set-load-path!)
        (only-in :clan/poo/object .def .o .get .ref .put! .slot? .call object?
                 replay-slot-reads! object-read-issued?)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
                 slot-read-key slot-read-dependencies)
        (only-in :gerbil/expander eval-syntax datum->syntax current-expander-context make-top-context
                 core-import-module core-expand expander-context-id
                 current-expander-eval module-context? module-context-path module-context-code
                 core-context-prelude core-module->prelude-context expander-context-table)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/building/source-closure
                 for-each-build-module yuanxu-bootstrap-contexts yuanxu-bootstrap-source-path)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (rename-in (only-in :yuanxu/module-system/source/declaration .def) (.def publication-definition))
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        :yuanxu/module-system/source/objects
        (only-in :yuanxu/module-system/source/collection
                 make-yuanxu-module-source-collection yuanxu-module-source-collection-locate)
        :yuanxu/module-system/source/admission
        (only-in :yuanxu/module-system/source/publication ModulePublicationContract
                 module-publication-contract-current?)
        :yuanxu/module-system/source/preparation
        :yuanxu/module-system/interface)
(import (only-in "./fixtures.ss" write-file remove-tree with-publication-source domain-entry-count native-import-value exception-message PublicLibraryFixture core-source-root))
(export register-reader-root-collection-cases! register-build-support-control-cases!)

(def (register-reader-root-collection-cases!)
  (yuanxu-test-case "publication keeps unique original reads and refuses changed provenance"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def reader (module-publication-reader))
          (def counts #f)
          (def (observe key _amount)
            (when (and (pair? key) (eq? (car key) 'reader-read-roots))
              (set! counts (cdr key))))
          (defvalues (_publication reads)
            (parameterize ((current-module-source-observer observe))
              (%call-with-recorded-slot-reads (cut .call reader read source) unique-roots?: #t)))
          (def bundle (find (lambda (read) (eq? (slot-read-key read) 'publication-reads)) reads))
          ;; The former synthetic bundle is not an authority or a dependency.
          (check-equal? bundle #f)
          (def roots reads)
          (def seen (make-hash-table-eq))
          (for-each (lambda (read)
                      (check-equal? (hash-key? seen read) #f)
                      (hash-put! seen read #t)) roots)
          (check-equal? (andmap object-read-issued? roots) #t)
          (check-equal? (> (cdr (assq 'identities counts)) 0) #t)
          ;; The outer frame also observes acquisition of the reader function.
          (check-equal? (>= (length roots) (cdr (assq 'identities counts))) #t)
          ;; Root storage is now compact at collection time. Slot observers
          ;; still receive every delivery; this counter measures stored roots.
          (check-equal? (cdr (assq 'stored-roots counts)) (cdr (assq 'identities counts)))
          (replay-slot-reads! roots (lambda (_receiver _key) (void)))
          ;; Mutation is a negative injection, not a different source fixture.
          ;; No token is rebuilt and no callback's dependencies are filtered.
          (.put! source 'value "changed-after-publication")
          (check-exception
            (replay-slot-reads! roots (lambda (_receiver _key) (void))) error?))))
  (yuanxu-test-case "reader warm inputs preserve the original graph without a weak projection claim"
      (with-publication-source
        (lambda (_root _module-root source view)
          (def reader (module-publication-reader))
          (defvalues (_publication roots)
            (%call-with-recorded-slot-reads (cut .call reader read source) unique-roots?: #t))
          (let ()
            (def first (.call reader inputs source))
            (check-equal? (pair? first) #t)
            (.call reader read source)
            (def second (.call reader inputs source))
            ;; The same guarded native inputs are projected again, not cloned
            ;; sources or reused success. Existing currentness controls remain.
            (check-equal? (length second) (length first))
            (for-each (lambda (input) (check-equal? (if (memq input first) #t #f) #t)) second)
            (check-equal? (andmap object-read-issued? roots) #t)
            ;; Full graph retention is intentional. Do not resurrect the old
            ;; zero-closure telemetry as a passing memory optimization.
            (check-equal? (any (lambda (read) (pair? (slot-read-dependencies read))) roots) #t)
            (replay-slot-reads! roots (lambda (_receiver _key) (void))))
          ;; The real paired reader publishes its native support guard. No
          ;; synthetic reads, hand-maintained requirements or purity labels.
          (def candidate-reader (module-publication-reader))
          (def result
            (parameterize ((current-module-source-observer #f))
              (.call candidate-reader read-candidate (lambda () source)
                'custom/example (.get view context))))
          (def current! (list-ref result 4))
          (defvalues (_checked times)
            (parameterize ((current-module-source-observer #f))
              (call-with-module-source-operation-measurement current!)))
          (check-equal? (hash-ref times '(calls metadata-replay)) 2)
          (check-equal? (> (hash-ref times '(visits metadata-replay)) 0) #t)
          (check-equal? (number? (hash-ref times '(collections metadata-replay))) #t)
          (def replays 0)
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (when (equal? key '(metadata-replay-end native))
                              (set! replays (+ replays amount))))))
            (current!))
          (check-equal? replays 3)
          ;; A callback can edit a preparation-only dependency and remove its
          ;; own observer after admission replay. The pinned open tail remains.
          (set! replays 0)
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (when (equal? key '(metadata-replay-end native))
                              (set! replays (+ replays amount))
                              (when (= replays 2)
                                (.put! source 'value "changed-after-admission-replay")
                                (current-module-source-observer #f))))))
            (check-exception (current!)
              (lambda (failure)
                (and (Error? failure)
                     (equal? (Error-message failure) "stale slot dependency")))))
          (check-equal? replays 2)))))

(def (register-build-support-control-cases!)
  (yuanxu-test-case "tool eligibility does not enlarge the declaration dependency closure"
      (with-publication-source
       (lambda (_root module-root source _view)
         (def projection
           (path-normalize (yuanxu-bootstrap-source-path
             (core-import-module ':yuanxu/module-system/building/build-projection) core-source-root)))
         (def dependencies (make-hash-table))
         (for-each-build-module
           (core-import-module ':yuanxu/module-system/building/build-projection)
           (lambda (context)
             (let (path (yuanxu-bootstrap-source-path context core-source-root))
               (when path (hash-put! dependencies (path-normalize path) #t)))))
         (def (observed-paths reader)
           (def paths (make-hash-table))
           (parameterize ((current-module-source-observer
                           (lambda (key _amount)
                             (when (and (pair? key) (eq? (car key) 'file-read))
                               (hash-put! paths (path-normalize (caddr key)) #t)))))
             (.call reader admit-current))
           paths)
         (def reader (module-publication-reader))
         ;; The import eligibility catalog is not the consumer dependency set.
         (check-equal? (hash-key? (observed-paths reader) projection) #f)
         (.call reader read source)
         (check-equal? (hash-key? (observed-paths reader) projection) #f)
         ;; Changing a role requires a fresh reader. Its actual import must
         ;; register the entire native transitive closure, not only the root.
         (write-file (path-expand "build.ss" module-root)
           "(import (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)) (.def Build function: yuanxu-project-source-spec)")
         (write-file (path-expand "interface.ss" module-root)
           "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o (:: @ FixtureScope) greeting: Greeting) configuration-build: Build) features: (.o))")
         (def demanded (module-publication-reader))
         (def published (.call demanded read source))
         (check-equal? (hash-key? (observed-paths demanded) projection) #f)
         ;; The deferred Build evaluator must enroll its support in the same
         ;; publication reader before returning a callable/object to the Graph.
         (check-equal?
           (parameterize ((current-module-build-phase? #t))
             (procedure? (.get published core configuration-build function))) #t)
         (def paths (observed-paths demanded))
         (check-equal? (hash-key? paths projection) #t)
         ;; Compare the entire real native dependency closure, rather than a
         ;; former compiler-bootstrap helper no longer imported by this owner.
         (for-each (lambda (entry) (check-equal? (hash-key? paths (car entry)) #t))
                   (hash->list dependencies))
         ;; A topology hit still requires fresh byte reads on a later check.
         (check-equal? (hash-key? (observed-paths demanded) projection) #t)
         (write-file (path-expand "config.ss" module-root)
           "(def Greeting \"changed after demand\") (export Greeting)")
         (check-exception (.call demanded admit-current)
           (lambda (exception)
             (and (Error? exception)
                  (string=? (Error-message exception)
                    "compiler tool source changed; use a fresh reader"))))))))
