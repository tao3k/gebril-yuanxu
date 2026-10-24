;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/source this-source-file)
        (only-in :std/list/list find)
        (only-in :std/error Error? Error-message)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :gerbil/runtime/loader load-path set-load-path!)
        (only-in :clan/poo/object .def .o .get .ref .put! .slot? .call object?
                 replay-slot-reads! object-read-issued?)
        (only-in :clan/poo/mop Type. TypeError?)
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
(import (only-in "qualification/module-publication/fixtures.ss" write-file remove-tree with-publication-source domain-entry-count native-import-value exception-message PublicLibraryFixture core-source-root)
        (only-in "qualification/module-publication/controls.ss" register-reader-root-collection-cases! register-build-support-control-cases!))
(export module-publication-test)
(def ScopeContract
  (yuanxu-predicate-contract 'test/publication-scope object? (lambda (_v _c) '())))
(def factory-calls 0)
(def dependencies 'author-value)

(def native-.ref 'author-shadow)
(publication-definition Published
  identity: 'custom/published
  core: (.o requires: (.o Provider: (.o module-id: 'core/provider contract: ScopeContract))
            scope-contract: ScopeContract label: 'parent
            exports: (begin (set! factory-calls (+ factory-calls 1))
                            (.o value: label provider: Provider author: dependencies
                                unused: (error "unused export must remain lazy"))))
  features: (.o unused: (error "unused feature must remain lazy")))

(def module-publication-test
  (test-suite "Hygienic Module publication over admitted sources"
    (yuanxu-test-case "dependency bindings consume the native checked Scope callback"
      (with-publication-source
        (lambda (root _module-root _source _view)
          (def provider (path-expand "modules/custom/provider" root))
          (def consumer (path-expand "modules/custom/consumer" root))
          (def plain
            "(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)) (def ScopeContract (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '()))) (export ScopeContract)")
          (write-file (path-expand "types.ss" provider) plain)
          (write-file (path-expand "objects.ss" provider)
            "(import :clan/poo/object) (def calls 0) (def Scope (.o run: (lambda (value) (set! calls (+ calls 1)) value) .calls: (lambda () calls))) (export Scope)")
          (write-file (path-expand "config.ss" provider) "(def Config #f) (export Config)")
          (write-file (path-expand "interface.ss" provider)
            "(.def Provider identity: 'custom/provider core: (.o requires: (.o) scope-contract: ScopeContract exports: Scope) features: (.o))")
          (write-file (path-expand "types.ss" consumer)
            (string-append plain
              " (import (only-in :yuanxu/object-types/contracts YuanxuContract.) (only-in :clan/poo/mop Function) (only-in :clan/poo/number Integer) (only-in :clan/poo/type Record))"
              " (def CheckedDependency (.cc YuanxuContract. identity: 'test/checked-dependency value-contract: (Record run: (list (Function (list Integer) (list Integer)))))) (export CheckedDependency)"))
          (write-file (path-expand "objects.ss" consumer) "(def Placeholder #f) (export Placeholder)")
          (write-file (path-expand "config.ss" consumer) "(def Config #f) (export Config)")
          (write-file (path-expand "interface.ss" consumer)
            "(.def Consumer identity: 'custom/consumer core: (.o requires: (.o Provider: (.o module-id: 'custom/provider contract: CheckedDependency)) scope-contract: ScopeContract exports: (.o provider: Provider run: (lambda (value) (.call Provider run value)))) features: (.o))")
          (write-file (path-expand "init.ss" root)
            "(yuanxu! :load-modules \"./modules\" mode: explicit :custom (provider) (consumer))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def record (.call view .selected-record 'custom/consumer))
          (def scope (.get record scope))
          (check-exception (.call scope run "bad") TypeError?)
          (check-equal? (.call (.get scope provider) .calls) 0)
          (check-equal? (.call scope run 8) 8)
          (check-equal? (.call (.get scope provider) .calls) 1)
          (check-equal?
            (eq? (.get scope provider)
                 (.get record dependency-records Provider requirement-evidence candidate)) #t))))
    (yuanxu-test-case "Graph consumes the exact normalized publication from its single producer"
      (with-publication-source
        (lambda (root _module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def original (.get ModulePublicationContract value-contract))
          (def checked #f)
          (def calls 0)
          (def ValueContract
            (.o (:: @ Type.)
              .element?: object?
              .validate:
              (lambda (value)
                (set! calls (+ calls 1))
                (set! checked
                  (.o (:: @ value)
                    core:
                    (.o (:: @ (.get value core))
                      link: (lambda (_dependencies) (.o greeting: "normalized")))))
                checked)))
          ;; Test-only installation on the actual public Contract. The
          ;; producer remains unchanged and must normalize exactly once.
          (dynamic-wind
            (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
            (lambda ()
              (def record (.call view .selected-record 'custom/example))
              (check-equal? calls 1)
              (check-equal? (eq? (.get record publication) checked) #t)
              (check-equal? (eq? (.get record publication-evidence candidate) checked) #t)
              (check-equal? (.get record scope greeting) "normalized")
              (check-equal? (eq? record (.call view .selected-record 'custom/example)) #t)
              (check-equal? calls 1))
            (lambda () (.put! ModulePublicationContract 'value-contract original))))))
    (yuanxu-test-case "normalized publication owner mismatch is refused before Graph insertion"
      (with-publication-source
        (lambda (root _module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def original (.get ModulePublicationContract value-contract))
          (def ValueContract
            (.o (:: @ Type.)
              .element?: object?
              .validate: (lambda (value) (.o (:: @ value) identity: 'custom/wrong-owner))))
          (dynamic-wind
            (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
            (lambda ()
              (check-equal?
                (if (string-contains
                      (exception-message (lambda () (.get view selected-graph)))
                      "publication source owner mismatch") #t #f) #t))
            (lambda () (.put! ModulePublicationContract 'value-contract original))))))
    (yuanxu-test-case "publication normalization cannot carry a source mutation into the Graph"
      (with-publication-source
        (lambda (root module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def original (.get ModulePublicationContract value-contract))
          (def calls 0)
          (def ValueContract
            (.o (:: @ Type.)
              .element?: object?
              .validate:
              (lambda (value)
                (set! calls (+ calls 1))
                (write-file (path-expand "config.ss" module-root)
                  "(def Greeting \"changed by normalization\") (export Greeting)")
                (.o (:: @ value)))))
          (dynamic-wind
            (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
            (lambda ()
              (check-exception (.get view selected-graph) error?)
              (check-equal? calls 1)
              ;; The failed attempt never becomes a cached accepted Graph;
              ;; restoring a Contract does not revive the refused session.
              (check-exception (.call view .selected-record 'custom/example) error?)
              (check-equal? calls 1))
            (lambda () (.put! ModulePublicationContract 'value-contract original))))))
    (yuanxu-test-case "extended publication Contracts retain guards before declaration or Feature callbacks"
      (for-each
        (lambda (boundary)
          (with-publication-source
            (lambda (root module-root _source _view)
              (def marker (path-expand "must-not-execute" root))
              (write-file (path-expand "init.ss" root)
                (if (eq? boundary 'declaration)
                  "(yuanxu! mode: explicit :custom (example) (other))"
                  "(yuanxu! mode: explicit :custom (example +ci))"))
              (if (eq? boundary 'declaration)
                (let (other (path-expand "modules/custom/other" root))
                  (for-each
                    (lambda (role)
                      (write-file (path-expand role other)
                        (module-source-read (path-expand role module-root))))
                    '("types.ss" "objects.ss"))
                  (write-file (path-expand "config.ss" other)
                    (string-append "(call-with-output-file " (object->string marker)
                      " (lambda (port) (display \"unexpected\" port))) (def Greeting \"other\") (export Greeting)"))
                  (write-file (path-expand "interface.ss" other)
                    "(.def Fixture identity: 'custom/other core: (.o requires: (.o) scope-contract: FixtureContract exports: FixtureScope) features: (.o))"))
                (write-file (path-expand "interface.ss" module-root)
                  (string-append
                    "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: FixtureScope) features: (.o ci: (begin (call-with-output-file "
                    (object->string marker)
                    " (lambda (port) (display \"unexpected\" port))) (error \"Feature executed before source refusal\"))))")))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (def original (.get ModulePublicationContract value-contract))
              (def calls 0)
              (def ValueContract
                (.o (:: @ Type.)
                  .element?: object?
                  .validate:
                  (lambda (value)
                    (set! calls (+ calls 1))
                    (write-file (path-expand "config.ss" module-root)
                      "(def Greeting \"changed before continuation\") (export Greeting)")
                    value)))
              (dynamic-wind
                (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
                (lambda ()
                  (check-equal? (module-publication-contract-current?) #f)
                  (check-exception (.get view selected-graph) error?)
                  (check-equal? calls 1)
                  (check-equal? (file-exists? marker) #f))
                (lambda () (.put! ModulePublicationContract 'value-contract original))))))
        '(declaration feature)))
    (yuanxu-test-case "publication identity remains an open computation after reader return"
      (with-publication-source
        (lambda (_root module-root source view)
          (def config (path-expand "config.ss" module-root))
          (def replacement "(def Greeting \"changed during metadata admission\") (export Greeting)")
          ;; Deliberately cold metadata: .def constructs the receiver without
          ;; executing this identity getter. Reading a publication is therefore
          ;; not a checked-value witness for the later Contract producer.
          (write-file (path-expand "interface.ss" module-root)
            (call-with-output-string
              (lambda (port)
                (write
                  `(.def Fixture
                     identity: (begin
                       (call-with-output-file (list path: ,config truncate: #t)
                         (lambda (out) (display ,replacement out)))
                       'custom/example)
                     core: (.o requires: (.o) scope-contract: FixtureContract
                               exports: FixtureScope)
                     features: (.o)) port))))
          ;; Use a fresh reader after writing the declaration. The mutation
          ;; must happen at actual Contract admission, not initial discovery.
          (def reader (module-publication-reader))
          (def publication (.call reader read source))
          (check-equal? (string-contains (module-source-read config) "changed during") #f)
          (check-equal? (yuanxu-validation-evidence-accepted?
                         (admit-module-publication! source 'custom/example publication (.get view context))) #t)
          (check-equal? (module-source-read config) replacement)
          (check-exception (.call reader admit-current) error?))))
    (yuanxu-test-case "Context admission is an open boundary after structural metadata checks"
      (with-publication-source
        (lambda (_root module-root source view)
          (def reader (module-publication-reader))
          (def publication (.call reader read source))
          (def calls 0)
          ;; Negative injection at the PUBLIC contextual obligation boundary.
          ;; A structural predicate returning true does not close this callback.
          (def context
            (.o (:: @ (.get view context))
              .contract-obligations:
              (lambda (contract _candidate)
                (when (eq? (.get contract identity) 'module/publication)
                  (set! calls (+ calls 1))
                  (write-file (path-expand "config.ss" module-root)
                    "(def Greeting \"changed during Context admission\") (export Greeting)"))
                '())))
          (check-equal? (.slot? context '.contract-obligations) #t)
          (check-equal? (yuanxu-validation-evidence-accepted?
                         (admit-module-publication! source 'custom/example publication context)) #t)
          (check-equal? calls 1)
          (check-exception (.call reader admit-current) error?))))
    (yuanxu-test-case "paired location admits authoring once before declaration evaluation"
      (with-publication-source
        (lambda (root _module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def original (.get yuanxu-default-module-style-policy validate))
          (def calls 0)
          (dynamic-wind
            (lambda ()
              (.put! yuanxu-default-module-style-policy 'validate
                (lambda arguments (set! calls (+ calls 1)) (apply original arguments))))
            (lambda ()
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (check-equal? (.get view selected-graph module-order) '(custom/example))
              (check-equal? calls 1))
            (lambda () (.put! yuanxu-default-module-style-policy 'validate original))))))
    (yuanxu-test-case "location support includes nested parser objects and their ancestors"
      (.def Parent location: 'original)
      (.def (Child @ Parent))
      (def current? (module-source-object-policy (list Child)))
      (check-equal? (current?) #t)
      (.put! Parent 'location 'changed)
      (check-equal? (current?) #f)
      (.put! Parent 'location 'original)
      (check-equal? (current?) #f)
      (with-publication-source
        (lambda (root _module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def row (car (.get view context intent decisions)))
          (.put! (.get row selection) 'selection-flags '(+unexpected))
          (check-exception (.get view selected-graph) error?)))
      (with-publication-source
        (lambda (root _module-root _source _view)
          (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def source (.call (.get view context) locate 'custom/example))
          (def original (.get source value))
          (.put! source 'value "changed-source.ss")
          (check-exception (.call view sources-current) error?)
          (.put! source 'value original)
          (check-exception (.call view sources-current) error?))))
    (yuanxu-test-case "an overridden locator cannot reuse the closed source prefix"
      (with-publication-source
        (lambda (root module-root _source _view)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! mode: explicit :custom (example) (other))")
          (def other (path-expand "modules/custom/other" root))
          (for-each
            (lambda (role)
              (write-file (path-expand role other) (module-source-read (path-expand role module-root))))
            '("types.ss" "objects.ss"))
          (def marker (path-expand "must-not-initialize" root))
          (write-file (path-expand "config.ss" other)
            (string-append "(call-with-output-file " (object->string marker)
              " (lambda (port) (display \"unexpected\" port))) (def Greeting \"other\") (export Greeting)"))
          (write-file (path-expand "interface.ss" other)
            "(.def Fixture identity: 'custom/other core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o greeting: Greeting)) features: (.o))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def context (.get view context))
          (def locate (.get context locate))
          ;; Establish a real earlier reader dependency without resolving the
          ;; selected Graph or initializing the second declaration.
          (.call context read-publication (locate 'custom/example))
          (check-equal? (file-exists? marker) #f)
          ;; A closed locator validates metadata, not all earlier source bytes.
          ;; The reader MUST perform its full entry check even on that path.
          (def first (locate 'custom/example))
          (def second (locate 'custom/other))
          (def control (module-publication-reader))
          (.call control read first)
          (def config-path (path-expand "config.ss" module-root))
          (def original-config (module-source-read config-path))
          (dynamic-wind
            (lambda () (write-file config-path "(def Greeting \"changed\") (export Greeting)"))
            (lambda ()
              (check-exception
                (call-with-values
                  (lambda () (.call control read-located (lambda () second)))
                  (lambda (_source _publication) 'unexpected-success)) error?)
              (check-equal? (file-exists? marker) #f))
            (lambda () (write-file config-path original-config)))
          (def calls 0)
          (.put! context 'locate
            (lambda (id)
              (set! calls (+ calls 1))
              (write-file (path-expand "config.ss" module-root)
                "(def Greeting \"changed\") (export Greeting)")
              (locate id)))
          (check-exception (.get view selected-graph) error?)
          (check-equal? calls 1)
          (check-equal? (file-exists? marker) #f))))
    (yuanxu-test-case "the source constructor prototype is part of closed-prefix support"
      (check-equal? (yuanxu-module-source-ref-construction-current?) #t)
      (dynamic-wind
        (lambda () (.put! yuanxu-module-source-ref-prototype 'prefix-test-marker #t))
        (lambda () (check-equal? (yuanxu-module-source-ref-construction-current?) #f))
        (lambda () (.put! yuanxu-module-source-ref-prototype 'prefix-test-marker #f)))
      (check-equal? (yuanxu-module-source-ref-construction-current?) #f))
    (yuanxu-test-case "interfaces share the SDK POO prelude without per-module alias copies"
      (with-publication-source
        (lambda (_root _module-root source _view)
          (def reader (module-publication-reader))
          (def prelude
            (core-module->prelude-context
              (core-import-module ':yuanxu/module-system/source/config-prelude)))
          (def native-eval (current-expander-eval))
          (def interfaces (make-hash-table-eq))
          (parameterize
              ((current-expander-eval
                 (lambda (program)
                   (def context (current-expander-context))
                   (call-with-values (cut native-eval program)
                     (lambda results
                       (when (and (module-context? context)
                                  (string? (module-context-path context))
                                  (string-suffix? "-interface.ss" (module-context-path context)))
                         (hash-put! interfaces context #t))
                       (apply values results))))))
            (.call reader read source)
            (.call reader read source))
          (check-equal? (hash-length interfaces) 2)
          (hash-for-each
            (lambda (context _seen)
              (check-equal? (eq? (core-context-prelude context) prelude) #t)
              ;; .o remains available through the shared native weak prelude;
              ;; its import alias is not copied into either local table.
              (check-equal? (hash-key? (expander-context-table context) '.o) #f)
              (check-equal? (hash-key? (expander-context-table context) '.def) #t))
            interfaces))))


    (register-reader-root-collection-cases!)
    (yuanxu-test-fixture "public source preparation is unique but admission remains fresh"
      (library PublicLibraryFixture)
      (with-publication-source
        (lambda (_root module-root source _view)
          (write-file (path-expand "objects.ss" module-root)
            (call-with-output-string
              (lambda (port)
                (write `(import (only-in ,(.get library path) ExternalValue)
                                (only-in :clan/poo/object .o)) port)
                (write '(def FixtureScope (.o retained: ExternalValue)) port)
                (write '(export FixtureScope) port))))
          ;; An explicit interface import is revisited on every declaration,
          ;; even when the native role contexts have already been evaluated.
          (write-file (path-expand "interface.ss" module-root)
            (string-append
              (call-with-output-string
                (cut write `(import (only-in ,(.get library path) ExternalValue)) <>))
              "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o value: ExternalValue)) features: (.o))"))
          (def requests 0)
          (def preparations 0)
          (def reader (module-publication-reader))
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (case key
                              ((public-preparation-requests) (set! requests (+ requests amount)))
                              ((public-preparation-walks) (set! preparations (+ preparations amount)))))))
            (def first (.call reader read source))
            (def first-preparations preparations)
            (def second (.call reader read source))
            (check-equal? (eq? first second) #f)
            (check-equal? (> requests preparations) #t)
            (check-equal? preparations first-preparations)
            (.call reader admit-current))
          ;; Do not modify the installed SDK. This external public source is
          ;; owned by the fixture and published through the real native resolver.
          (write-file (.get library path)
            "(def ExternalValue \"changed\") (export ExternalValue)")
          (check-exception (.call reader admit-current)
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception)
                     "public dependency source or native identity changed")))))))
    (yuanxu-test-fixture "warm public source refuses native name redirection"
      (library PublicLibraryFixture)
      (with-publication-source
        (lambda (_root module-root source _view)
          (write-file (path-expand "interface.ss" module-root)
            (string-append
              (call-with-output-string
                (cut write `(import (only-in ,(.get library path) ExternalValue)) <>))
              "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o value: ExternalValue)) features: (.o))"))
          (def reader (module-publication-reader))
          (.call reader read source)
          (set-load-path! (cons (.get library shadow) (load-path)))
          (check-exception (.call reader admit-current)
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception)
                     "public dependency source or native identity changed")))))))

    (register-build-support-control-cases!)
    (yuanxu-test-case "completed reader bodies release without discarding macro bindings"
      (with-publication-source
       (lambda (_root module-root source _view)
         (write-file (path-expand "objects.ss" module-root)
           "(import (only-in :clan/poo/object .o)) (defrules fixture-answer () ((_) 42)) (def FixtureScope (.o retained: 'upstream)) (export FixtureScope fixture-answer)")
         (def reader (module-publication-reader))
         (def sdk-context (core-import-module ':clan/poo/object))
         (def sdk-code (module-context-code sdk-context))
         (check-equal? (not (not sdk-code)) #t)
         (def native-eval (current-expander-eval))
         (def evaluated (make-hash-table-eq))
         (def runtime-state (make-hash-table-eq))
         (parameterize
             ((current-expander-eval
                (lambda (program)
                  (def context (current-expander-context))
                  (call-with-values (lambda () (native-eval program))
                    (lambda results
                      (when (module-context? context)
                        (hash-put! evaluated context (module-context-code context))
                        (hash-put! runtime-state context
                          (cons (slot-ref context 'e) (slot-ref context 'import))))
                      (apply values results))))))
           (.call reader read source))
         (def macro-context
           (find (lambda (context)
                   (let (path (module-context-path context))
                     (and (string? path) (string-suffix? "-objects.ss" path))))
                 (hash-keys evaluated)))
         (check-equal? (module-context? macro-context) #t)
         (check-equal? (module-context-code macro-context) #f)
         ;; Independent full native DFS is the oracle for the cut traversal.
         ;; Register every evaluated private wrapper, a superset of role inputs;
         ;; both projections must preserve exact order and identities.
         (def canonical (yuanxu-bootstrap-contexts))
         (def private (make-hash-table-eq))
         (hash-for-each
           (lambda (context _code)
             (let (path (module-context-path context))
               (when (and (string? path) (string-contains path "publication-reader-"))
                 (hash-put! private context #t)))) evaluated)
         (def full-visits 0)
         (def cut-visits 0)
         (def (keep? context)
           (not (eq? context (hash-get canonical (expander-context-id context)))))
         (hash-for-each
           (lambda (root _registered)
             (def full '())
             (def pruned '())
             (for-each-build-module root
               (lambda (context)
                 (set! full-visits (+ full-visits 1))
                 (when (hash-key? private context) (set! full (cons context full)))))
             (for-each-build-module root
               (lambda (context)
                 (set! cut-visits (+ cut-visits 1))
                 (when (hash-key? private context) (set! pruned (cons context pruned))))
               (make-hash-table-eq) keep?)
             (check-equal? (equal? full pruned) #t)) private)
         (check-equal? (< cut-visits full-visits) #t)
         (yuanxu-test-observe 'private-closure-oracle-visits full-visits)
         (yuanxu-test-observe 'private-closure-cut-visits cut-visits)
         (check-equal? (eq? sdk-code (module-context-code sdk-context)) #t)
         (hash-for-each
           (lambda (context state)
             (check-equal? (eq? (car state) (slot-ref context 'e)) #t)
             (check-equal? (eq? (cdr state) (slot-ref context 'import)) #t))
           runtime-state)
         ;; A second demand must use the original macro binding, after cleanup.
         (parameterize ((current-expander-context macro-context))
           (check-equal? (eval-syntax '(fixture-answer)) 42)
           (check-equal? (eval-syntax '(fixture-answer)) 42))
         ;; Reader cleanup must never erase canonical SDK/tool bodies.
         (hash-for-each
           (lambda (context code)
             (let (path (module-context-path context))
               (unless (and (string? path) (string-contains path "publication-reader-"))
                 (check-equal? (eq? code (module-context-code context)) #t))))
           evaluated)
         ;; Compilation projects original sources, independently of the private
         ;; reader body. Both original syntax and source currentness survive.
         (def prepared (.call reader preparation source))
         (check-equal? (pair? (.get prepared compiler-forms)) #t)
         (check-equal? (pair? (.get (yuanxu-prepare-module-build-source
                                    (path-expand "objects.ss" module-root) void)
                                  compiler-forms)) #t)
         (.call reader read source)
         (.call reader admit-current))))
    (yuanxu-test-case "failed post-evaluation source guard does not release reader bodies"
      (with-publication-source
       (lambda (_root module-root source _view)
         (def path (path-expand "config.ss" module-root))
         (write-file path
           (call-with-output-string
             (lambda (port)
               (write `(call-with-output-file (list path: ,path truncate: #t)
                         (lambda (out) (display "(def Greeting \"changed\")" out))) port)
               (write '(def Greeting "hello") port)
               (write '(export Greeting) port))))
         (def reader (module-publication-reader))
         (def native-eval (current-expander-eval))
         (def evaluated (make-hash-table-eq))
         (parameterize
             ((current-expander-eval
                (lambda (program)
                  (def context (current-expander-context))
                  (call-with-values (lambda () (native-eval program))
                    (lambda results
                      (when (module-context? context)
                        (hash-put! evaluated context (module-context-code context)))
                      (apply values results))))))
           (check-exception (.call reader read source) error?))
         (check-equal? (> (hash-length evaluated) 0) #t)
         (hash-for-each
           (lambda (context code)
             (check-equal? (eq? code (module-context-code context)) #t)) evaluated))))
    (yuanxu-test-case "symbolic owned imports keep one confined macro expansion"
      (with-publication-source
       (lambda (root module-root _source _view)
         (def package (cadr (call-with-input-file (path-expand "gerbil.pkg" root) read)))
         (def library
           (string->symbol (string-append ":" (symbol->string package)
                                          "/modules/custom/example/objects")))
         (def marker (path-expand "role-expanded" root))
         (write-file (path-expand "objects.ss" module-root)
           (call-with-output-string
             (lambda (port)
               ;; A duplicate compiler context must not execute the same macro
               ;; initializer before redirecting to its admitted private role.
               (write `(begin-syntax
                         (when (file-exists? ,marker) (error "role expanded twice"))
                         (call-with-output-file ,marker (lambda (out) (display "once" out)))) port)
               (write '(import (only-in :clan/poo/object .o)) port)
               (write '(def FixtureScope (.o retained: 'upstream)) port)
               (write '(export FixtureScope) port))))
         (write-file (path-expand "config.ss" module-root)
           (call-with-output-string
             (lambda (port)
               (write `(import (only-in ,library FixtureScope)) port)
               (write '(def Greeting "hello") port)
               (write '(export Greeting) port))))
         ;; Registration is local to the test; the SDK still resolves package
         ;; prefixes and the reader still enforces the original owner boundary.
         (def previous (load-path))
         (def closure-requests 0)
         (def closure-walks 0)
         (def demanded (make-hash-table-eq))
         (def discovered (make-hash-table-eq))
         (def kernel-requests 0)
         (def kernel-walks 0)
         (dynamic-wind
           (lambda () (add-load-path! root))
           (lambda ()
             (parameterize
               ((current-module-source-observer
                  (lambda (kind amount)
                    (cond ((eq? kind 'compiler-closure-requests)
                           (set! closure-requests (+ closure-requests amount)))
                          ((eq? kind 'compiler-closure-walks)
                           (set! closure-walks (+ closure-walks amount)))
                          ((and (pair? kind) (eq? (car kind) 'compiler-demand))
                           (hash-update! demanded (cadr kind) (cut + <> amount) 0))
                          ((and (pair? kind) (eq? (car kind) 'compiler-discovery))
                           (let (children (or (hash-get discovered (cadr kind))
                                             (let (table (make-hash-table-eq))
                                               (hash-put! discovered (cadr kind) table) table)))
                             (hash-update! children (caddr kind) (cut + <> amount) 0)))
                          ((eq? kind 'kernel-closure-requests)
                           (set! kernel-requests (+ kernel-requests amount)))
                          ((eq? kind 'kernel-closure-walks)
                           (set! kernel-walks (+ kernel-walks amount)))))))
               (let (view (yuanxu-load-modules (path-expand "modules" root)))
                 (check-equal? (.get view modules custom example greeting) "hello")
                 (check-equal? (call-with-input-file marker read-line) "once")
                 (check-equal? (> closure-walks 0) #t)
                 (check-equal? (> closure-requests closure-walks) #t)
                 ;; Actual SDK identities, not a hand-maintained dependency list:
                 ;; every child is first-discovered once per requested closure.
                 (check-equal? (> (hash-length discovered) 0) #t)
                 (check-equal? (andmap
                                (lambda (row)
                                  (andmap (lambda (child) (= (cdr child) 1))
                                          (hash->list (cdr row))))
                                (hash->list discovered)) #t)
                 (check-equal? (ormap (lambda (row) (> (cdr row) 1)) (hash->list demanded)) #t)
                 (check-equal? (> kernel-walks 0) #t)
                 ;; Private projections now stream on every demand. Only the
                 ;; independent canonical compiler-tool index keeps closures.
                 (check-equal? kernel-requests kernel-walks)
                 ;; Negative control: the SDK's independent canonical context
                 ;; really would rerun the initializer if confinement were lost.
                 (check-exception (core-import-module library) error?)
                 (check-equal? (call-with-input-file marker read-line) "once"))))
           (lambda () (set-load-path! previous))))))
    (yuanxu-test-case "default reader selects and builds source roles without compiled selected modules"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
         (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
                (graph (.get view build-graph)))
           (check-equal? (.get view selected-graph module-order) '(custom/example))
           (check-equal? (domain-entry-count graph module-root) 4)
           (check-equal? (.get view modules custom example greeting) "hello")
           (check-equal? (.get view modules custom example retained) 'upstream)))))
    (yuanxu-test-case "metadata selection never invokes domain exports or unselected source"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example) (bomb disable: #t))")
         (write-file (path-expand "modules/custom/bomb/interface.ss" root) "(((not readable")
         (write-file (path-expand "interface.ss" module-root)
           "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (error \"domain scope must remain deferred\")) features: (.o cold: (error \"unselected feature forced\")))")
         (let ((view (yuanxu-load-modules (path-expand "init.ss" root)))
               (output (path-expand "generated" root)))
           (check-equal? (.get view selected-graph module-order) '(custom/example))
           (check-equal? (domain-entry-count (.get view build-graph) module-root) 4)))))
    (yuanxu-test-case "new source sessions do not reuse stale native role namespaces"
      (with-publication-source
       (lambda (root module-root _source view)
         (check-equal? (.get view modules custom example greeting) "hello")
         (write-file (path-expand "config.ss" module-root) "(def Greeting \"changed\") (export Greeting)")
         (check-exception ((.get view admit-current)) error?)
         (let (next (yuanxu-load-modules (path-expand "modules" root)))
           (check-equal? (.get next modules custom example greeting) "changed")))))
    (yuanxu-test-case "publication reader refuses bootstrap self imports and mismatched source identity"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(yuanxu! mode: explicit :custom (example))")
         (let* ((path (path-expand "interface.ss" module-root))
                (original (module-source-read path)))
           (write-file path (string-append "(import \"./interface.ss\") " original))
           (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
             (check-equal? (if (string-contains
                                 (exception-message (lambda () (.get view selected-graph)))
                                 "bootstrap cannot import its own interface") #t #f) #t))
           (write-file path
             "(.def Fixture identity: 'wrong/owner core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o)) features: (.o))")
           (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
             (check-exception (.get view build-graph) error?))))))
    (yuanxu-test-case "publication is deferred; native helpers and dependency identifiers are hygienic"
      (let* ((before factory-calls)
             (source (make-yuanxu-module-generated-source 'custom/published))
             (evidence (admit-module-publication! source 'custom/published Published (.o)))
             (provider (.o value: 'provider)))
        (check-equal? (yuanxu-validation-evidence-accepted? evidence) #t)
        (check-equal? factory-calls before)
        (check-equal? (.slot? (.get Published core) 'exports) #f)
        (let (scope ((.get Published core link) (.o Provider: provider)))
          (check-equal? factory-calls (+ before 1))
          (check-equal? (.get scope author) 'author-value)
          (check-equal? (.get scope value) 'parent)
          (check-equal? (eq? (.get scope provider) provider) #t))))
    (yuanxu-test-case "generated link wrappers consume only admitted dependency scopes"
      (let* ((before factory-calls)
             (AnyScope (yuanxu-predicate-contract 'test/any (lambda (_v) #t) (lambda (_v _c) '())))
             (provider (.o identity: 'core/provider features: (.o)
                           core: (.o requires: (.o) scope-contract: AnyScope link: (lambda (_deps) 42))))
             (view (yuanxu-load-modules
                    (.o generation: "publication-dependency-test" module-ids: '(core/provider custom/published)
                        selected: '(custom/published) denied-modules: '()
                        locate: make-yuanxu-module-generated-source
                        current?: (lambda (_generation) #t)
                        read-publication: (lambda (source)
                                            (if (eq? (yuanxu-module-source-ref-value source) 'core/provider)
                                              provider Published))))))
        (check-exception (.get view selected-records) error?)
        (check-equal? factory-calls before)))
    (yuanxu-test-case "cached parent link retains native effective outer-slot binding in child"
      (let (parent-link (.get Published core link))
        (.def (Child @ Published) core: =>.+ (.o label: 'child))
        (let (bindings (.o Provider: (.o)))
          (check-equal? (.get (parent-link bindings) value) 'parent)
          (check-equal? (.get ((.get Child core link) bindings) value) 'child)
          (check-equal? (.get (parent-link bindings) value) 'parent))))
    (yuanxu-test-case "prepared wrapper imports roles and exports only the Module automatically"
      (with-publication-source
       (lambda (root module-root source view)
         (let* ((prepared ((.get view prepare-publication) 'custom/example))
                (wrapper (path-expand "compiled/interface.ss" root)))
           (check-equal? (.get prepared binding) 'Fixture)
           (check-equal? (eq? prepared ((.get view prepare-publication) 'custom/example)) #t)
           (yuanxu-write-module-publication prepared wrapper)
           (let (publication (native-import-value wrapper 'Fixture))
             (check-equal? (expander-context-id (core-import-module wrapper)) (.get prepared compiler-identity))
             (check-equal? (yuanxu-validation-evidence-accepted?
                           (admit-module-publication! source 'custom/example publication (.o))) #t)
             (let (scope ((.get publication core link) (.o)))
               (check-equal? (.get scope greeting) "hello")
               (check-equal? (.get scope retained) 'upstream)))
           (check-exception (native-import-value wrapper 'Greeting) true)
           (let* ((original (path-expand "interface.ss" module-root))
                  (text (module-source-read original)))
             (check-exception (yuanxu-write-module-publication prepared original) error?)
             (check-equal? (module-source-read original) text))))))
    (yuanxu-test-case "collection and directory sources derive the same compiler boundary"
      (with-publication-source
       (lambda (root module-root source view)
         (let* ((collection (make-yuanxu-module-source-collection 'fixture 'test root "modules/custom"))
                (other-source (car (yuanxu-module-source-collection-locate collection '(custom . example))))
                (directory ((.get view prepare-publication) 'custom/example))
                (contribution (yuanxu-prepare-module-publication other-source)))
           (check-equal? (.get directory compiler-forms) (.get contribution compiler-forms))
           (check-equal? (.get directory compiler-identity) (.get contribution compiler-identity))))))
    (yuanxu-test-case "manual export inventories and computed top-level declarations are refused"
      (for-each
       (lambda (extra)
         (with-publication-source
          (lambda (root module-root source view)
            (let (file (path-expand "interface.ss" module-root))
              (write-file file (string-append (module-source-read file) extra)))
            (let (message (exception-message (lambda () (yuanxu-prepare-module-publication source))))
              (check-equal? (if (string-contains message "interface.ss must contain one Module .def") #t #f) #t)))))
       '(" (export Fixture)" " (begin (error \"must not evaluate\"))")))
    (yuanxu-test-case "unchanged publication identity is parsed once; changed header and closer package refuse"
      (with-publication-source
       (lambda (_root module-root source _view)
         (def identity-reads 0)
         (parameterize ((current-module-source-observer
                         (lambda (kind amount)
                           (when (eq? kind 'compiler-identity-reads)
                             (set! identity-reads (+ identity-reads amount))))))
           (def prepared (yuanxu-prepare-module-publication source))
           (check-equal? identity-reads 1)
           (for-each (lambda (_) ((.get prepared admit-current))) '(1 2 3 4 5))
           (check-equal? identity-reads 1)
           (def file (path-expand "interface.ss" module-root))
           (write-file file (string-append "namespace: changed\n" (module-source-read file)))
           (check-exception ((.get prepared admit-current)) error?))))
      (with-publication-source
       (lambda (_root module-root source _view)
         (def prepared (yuanxu-prepare-module-publication source))
         (write-file (path-expand "gerbil.pkg" module-root) "(package: closer)")
         (check-exception ((.get prepared admit-current)) error?))))
    (yuanxu-test-case "source preparation does not initialize role values and stale sources refuse output"
      (with-publication-source
       (lambda (root module-root source view)
         (write-file (path-expand "config.ss" module-root) "(def Greeting (error \"must not initialize\")) (export Greeting)")
         (let (prepared (yuanxu-prepare-module-publication source))
           ((.get prepared admit-current))
           (write-file (path-expand "config.ss" module-root) "(def Greeting \"changed\") (export Greeting)")
           (check-exception (yuanxu-write-module-publication prepared (path-expand "stale/interface.ss" root)) error?)
           (check-equal? (module-source-type (path-expand "stale/interface.ss" root)) #f)))))
    (yuanxu-test-case "init changes invalidate a prepared compiler input held by the caller"
      (with-publication-source
       (lambda (root module-root source view)
         (let ((prepared ((.get view prepare-publication) 'custom/example))
               (output (path-expand "stale-selection/interface.ss" root)))
           (write-file (path-expand "init.ss" root)
                       "(yuanxu! mode: auto source: \"./modules\" :custom (example disable: #t))")
           (check-exception (yuanxu-write-module-publication prepared output) error?)
           (check-equal? (module-source-type output) #f)))))
    (yuanxu-test-case "package source edits and disabled Modules refuse compiler preparation"
      (with-publication-source
       (lambda (root module-root source view)
         (let ((prepared ((.get view prepare-publication) 'custom/example))
               (package (path-expand "gerbil.pkg" root)))
           (write-file package (string-append (module-source-read package) "\n; changed generation\n"))
           (check-exception ((.get prepared admit-current)) error?))
         (write-file (path-expand "init.ss" root)
                     "(yuanxu! mode: auto source: \"./modules\" :custom (example disable: #t))")
         (let (disabled (yuanxu-load-modules (path-expand "modules" root)))
           (check-exception ((.get disabled prepare-publication) 'custom/example) error?)))))
    (yuanxu-test-case "macro errors retain the original included interface location"
      (with-publication-source
       (lambda (root module-root source view)
         (write-file (path-expand "interface.ss" module-root)
           "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o greeting:)) features: (.o))")
         ;; The malformed text belongs to a fresh source generation; a held
         ;; SourceRef from before the edit is expected to refuse as stale.
         (let* ((fresh (yuanxu-load-modules (path-expand "modules" root)))
                (fresh-source ((.get fresh context locate) 'custom/example))
                (prepared (yuanxu-prepare-module-publication fresh-source))
                (wrapper (path-expand "invalid/interface.ss" root)))
           (yuanxu-write-module-publication prepared wrapper)
           (let (message (exception-message (lambda () (core-import-module wrapper))))
             (unless (string-contains message (path-expand "interface.ss" module-root))
               (displayln "MACRO-ERROR-ORIGIN " message) (force-output))
             (check-equal? (if (string-contains message (path-expand "interface.ss" module-root)) #t #f) #t))))))
    (yuanxu-test-case "duplicate fields, inherited dependencies and hand-written link wrappers are rejected"
      (for-each
       (lambda (example)
         (let (message
               (exception-message
                (lambda ()
                  (core-expand
                   (datum->syntax (quote-syntax publication-definition)
                     `(publication-definition Invalid identity: 'invalid core: ,(car example) features: (.o)))))))
           (check-equal? (if (string-contains message (cdr example)) #t #f) #t)))
       (list
        (cons '(.o requires: (.o) scope-contract: ScopeContract exports: (.o) exports: (.o)) "duplicate publication field")
        (cons '(.o requires: (.o (:: @ Published)) scope-contract: ScopeContract exports: (.o)) "without inherited aliases")
        (cons '(.o requires: (.o) scope-contract: ScopeContract exports: (.o) link: values) "core.link is generated"))))))
