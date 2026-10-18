;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/list/list find)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .def .o .get .ref .slot? .call object?)
        (only-in :gerbil/expander eval-syntax datum->syntax current-expander-context make-top-context
                 core-import-module core-expand expander-context-id
                 current-expander-eval module-context? module-context-path module-context-code)
        (only-in :core/module-system/source/reader module-publication-reader)
        (only-in :core/module-system/source/preparation poo-flow-prepare-module-build-source)
        (rename-in (only-in :core/module-system/source/declaration .def) (.def publication-definition))
        (only-in :core/types poo-flow-predicate-contract poo-flow-validation-evidence-accepted?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        :core/module-system/source/objects
        (only-in :core/module-system/source/collection
                 make-poo-flow-module-source-collection poo-flow-module-source-collection-locate)
        :core/module-system/source/admission
        :core/module-system/source/preparation
        :core/module-system/interface)
(export module-publication-test)
(def ScopeContract
  (poo-flow-predicate-contract 'test/publication-scope object? (lambda (_v _c) '())))
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
(def (write-file path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port))))
(def (remove-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-tree (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (with-publication-source test)
  (let* ((root (make-temporary-file-name "module-publication-"))
         (module-root (path-expand "modules/custom/example" root)))
    (dynamic-wind
     (lambda ()
       (write-file (path-expand "gerbil.pkg" root)
                   (string-append "(package: " (symbol->string (gensym 'publication-fixture-)) ")"))
       (write-file (path-expand "types.ss" module-root)
         "(import (only-in :core/types poo-flow-predicate-contract) (only-in :clan/poo/object object?)) (def FixtureContract (poo-flow-predicate-contract 'fixture object? (lambda (_v _c) '()))) (export FixtureContract)")
       (write-file (path-expand "objects.ss" module-root)
         "(import (only-in :clan/poo/object .o)) (def FixtureScope (.o retained: 'upstream)) (export FixtureScope)")
       (write-file (path-expand "config.ss" module-root)
         "(def Greeting \"hello\") (export Greeting)")
       (write-file (path-expand "interface.ss" module-root)
         "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o (:: @ FixtureScope) greeting: Greeting)) features: (.o))"))
     (lambda ()
       (let* ((view (poo-flow-load-modules (path-expand "modules" root)))
              (source ((.get view context locate) 'custom/example)))
         (test root module-root source view)))
     (lambda () (remove-tree root)))))
(def (domain-entry-count graph root)
  ;; Compiler-tool inputs now accompany domain roots. Keep the source-role
  ;; assertion exact without pretending tools are application Module roles.
  (let (prefix (string-append (path-strip-trailing-directory-separator (path-normalize root)) "/"))
    (length (filter (lambda (entry) (string-prefix? prefix (path-normalize (.get entry path))))
                    (.get graph entries)))))
(def (native-import-value path name)
  ;; Test-only native compiler/interpreter control, not a runtime Loader backend.
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax `(import ,path))
    (eval-syntax name)))
(def (exception-message thunk)
  (with-catch (lambda (exception)
                (call-with-output-string (lambda (port) (display-exception exception port))))
              (lambda () (thunk) "unexpected success")))
(def module-publication-test
  (test-suite "Hygienic Module publication over admitted sources"
    (poo-flow-test-case "completed reader bodies release without discarding macro bindings"
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
         (check-equal? (pair? (.get (poo-flow-prepare-module-build-source
                                    (path-expand "objects.ss" module-root) void)
                                  compiler-forms)) #t)
         (.call reader read source)
         (.call reader admit-current))))
    (poo-flow-test-case "failed post-evaluation source guard does not release reader bodies"
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
    (poo-flow-test-case "symbolic owned imports keep one confined macro expansion"
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
               (let (view (poo-flow-load-modules (path-expand "modules" root)))
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
                 (check-equal? (> kernel-requests kernel-walks) #t)
                 ;; Negative control: the SDK's independent canonical context
                 ;; really would rerun the initializer if confinement were lost.
                 (check-exception (core-import-module library) error?)
                 (check-equal? (call-with-input-file marker read-line) "once"))))
           (lambda () (set-load-path! previous))))))
    (poo-flow-test-case "default reader selects and builds source roles without compiled selected modules"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(poo-flow! mode: explicit :custom (example))")
         (let* ((view (poo-flow-load-modules (path-expand "init.ss" root)))
                (graph (.get view build-graph)))
           (check-equal? (.get view selected-graph module-order) '(custom/example))
           (check-equal? (domain-entry-count graph module-root) 4)
           (check-equal? (.get view modules custom example greeting) "hello")
           (check-equal? (.get view modules custom example retained) 'upstream)))))
    (poo-flow-test-case "metadata selection never invokes domain exports or unselected source"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(poo-flow! mode: explicit :custom (example) (bomb disable: #t))")
         (write-file (path-expand "modules/custom/bomb/interface.ss" root) "(((not readable")
         (write-file (path-expand "interface.ss" module-root)
           "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (error \"domain scope must remain deferred\")) features: (.o cold: (error \"unselected feature forced\")))")
         (let ((view (poo-flow-load-modules (path-expand "init.ss" root)))
               (output (path-expand "generated" root)))
           (check-equal? (.get view selected-graph module-order) '(custom/example))
           (check-equal? (domain-entry-count (.get view build-graph) module-root) 4)))))
    (poo-flow-test-case "new source sessions do not reuse stale native role namespaces"
      (with-publication-source
       (lambda (root module-root _source view)
         (check-equal? (.get view modules custom example greeting) "hello")
         (write-file (path-expand "config.ss" module-root) "(def Greeting \"changed\") (export Greeting)")
         (check-exception ((.get view admit-current)) error?)
         (let (next (poo-flow-load-modules (path-expand "modules" root)))
           (check-equal? (.get next modules custom example greeting) "changed")))))
    (poo-flow-test-case "publication reader refuses bootstrap self imports and mismatched source identity"
      (with-publication-source
       (lambda (root module-root _source _view)
         (write-file (path-expand "init.ss" root) "(poo-flow! mode: explicit :custom (example))")
         (let* ((path (path-expand "interface.ss" module-root))
                (original (module-source-read path)))
           (write-file path (string-append "(import \"./interface.ss\") " original))
           (let (view (poo-flow-load-modules (path-expand "init.ss" root)))
             (check-equal? (if (string-contains
                                 (exception-message (lambda () (.get view selected-graph)))
                                 "bootstrap cannot import its own interface") #t #f) #t))
           (write-file path
             "(.def Fixture identity: 'wrong/owner core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o)) features: (.o))")
           (let (view (poo-flow-load-modules (path-expand "init.ss" root)))
             (check-exception (.get view build-graph) error?))))))
    (poo-flow-test-case "publication is deferred; native helpers and dependency identifiers are hygienic"
      (let* ((before factory-calls)
             (source (make-poo-flow-module-generated-source 'custom/published))
             (evidence (admit-module-publication! source 'custom/published Published (.o)))
             (provider (.o value: 'provider)))
        (check-equal? (poo-flow-validation-evidence-accepted? evidence) #t)
        (check-equal? factory-calls before)
        (check-equal? (.slot? (.get Published core) 'exports) #f)
        (let (scope ((.get Published core link) (.o Provider: provider)))
          (check-equal? factory-calls (+ before 1))
          (check-equal? (.get scope author) 'author-value)
          (check-equal? (.get scope value) 'parent)
          (check-equal? (eq? (.get scope provider) provider) #t))))
    (poo-flow-test-case "generated link wrappers consume only admitted dependency scopes"
      (let* ((before factory-calls)
             (AnyScope (poo-flow-predicate-contract 'test/any (lambda (_v) #t) (lambda (_v _c) '())))
             (provider (.o identity: 'core/provider features: (.o)
                           core: (.o requires: (.o) scope-contract: AnyScope link: (lambda (_deps) 42))))
             (view (poo-flow-load-modules
                    (.o generation: "publication-dependency-test" module-ids: '(core/provider custom/published)
                        selected: '(custom/published) denied-modules: '()
                        locate: make-poo-flow-module-generated-source
                        current?: (lambda (_generation) #t)
                        read-publication: (lambda (source)
                                            (if (eq? (poo-flow-module-source-ref-value source) 'core/provider)
                                              provider Published))))))
        (check-exception (.get view selected-records) error?)
        (check-equal? factory-calls before)))
    (poo-flow-test-case "cached parent link retains native effective outer-slot binding in child"
      (let (parent-link (.get Published core link))
        (.def (Child @ Published) core: =>.+ (.o label: 'child))
        (let (bindings (.o Provider: (.o)))
          (check-equal? (.get (parent-link bindings) value) 'parent)
          (check-equal? (.get ((.get Child core link) bindings) value) 'child)
          (check-equal? (.get (parent-link bindings) value) 'parent))))
    (poo-flow-test-case "prepared wrapper imports roles and exports only the Module automatically"
      (with-publication-source
       (lambda (root module-root source view)
         (let* ((prepared ((.get view prepare-publication) 'custom/example))
                (wrapper (path-expand "compiled/interface.ss" root)))
           (check-equal? (.get prepared binding) 'Fixture)
           (check-equal? (eq? prepared ((.get view prepare-publication) 'custom/example)) #t)
           (poo-flow-write-module-publication prepared wrapper)
           (let (publication (native-import-value wrapper 'Fixture))
             (check-equal? (expander-context-id (core-import-module wrapper)) (.get prepared compiler-identity))
             (check-equal? (poo-flow-validation-evidence-accepted?
                           (admit-module-publication! source 'custom/example publication (.o))) #t)
             (let (scope ((.get publication core link) (.o)))
               (check-equal? (.get scope greeting) "hello")
               (check-equal? (.get scope retained) 'upstream)))
           (check-exception (native-import-value wrapper 'Greeting) true)
           (let* ((original (path-expand "interface.ss" module-root))
                  (text (module-source-read original)))
             (check-exception (poo-flow-write-module-publication prepared original) error?)
             (check-equal? (module-source-read original) text))))))
    (poo-flow-test-case "collection and directory sources derive the same compiler boundary"
      (with-publication-source
       (lambda (root module-root source view)
         (let* ((collection (make-poo-flow-module-source-collection 'fixture 'test root "modules/custom"))
                (other-source (car (poo-flow-module-source-collection-locate collection '(custom . example))))
                (directory ((.get view prepare-publication) 'custom/example))
                (contribution (poo-flow-prepare-module-publication other-source)))
           (check-equal? (.get directory compiler-forms) (.get contribution compiler-forms))
           (check-equal? (.get directory compiler-identity) (.get contribution compiler-identity))))))
    (poo-flow-test-case "manual export inventories and computed top-level declarations are refused"
      (for-each
       (lambda (extra)
         (with-publication-source
          (lambda (root module-root source view)
            (let (file (path-expand "interface.ss" module-root))
              (write-file file (string-append (module-source-read file) extra)))
            (let (message (exception-message (lambda () (poo-flow-prepare-module-publication source))))
              (check-equal? (if (string-contains message "interface.ss must contain one Module .def") #t #f) #t)))))
       '(" (export Fixture)" " (begin (error \"must not evaluate\"))")))
    (poo-flow-test-case "unchanged publication identity is parsed once; changed header and closer package refuse"
      (with-publication-source
       (lambda (_root module-root source _view)
         (def identity-reads 0)
         (parameterize ((current-module-source-observer
                         (lambda (kind amount)
                           (when (eq? kind 'compiler-identity-reads)
                             (set! identity-reads (+ identity-reads amount))))))
           (def prepared (poo-flow-prepare-module-publication source))
           (check-equal? identity-reads 1)
           (for-each (lambda (_) ((.get prepared admit-current))) '(1 2 3 4 5))
           (check-equal? identity-reads 1)
           (def file (path-expand "interface.ss" module-root))
           (write-file file (string-append "namespace: changed\n" (module-source-read file)))
           (check-exception ((.get prepared admit-current)) error?))))
      (with-publication-source
       (lambda (_root module-root source _view)
         (def prepared (poo-flow-prepare-module-publication source))
         (write-file (path-expand "gerbil.pkg" module-root) "(package: closer)")
         (check-exception ((.get prepared admit-current)) error?))))
    (poo-flow-test-case "source preparation does not initialize role values and stale sources refuse output"
      (with-publication-source
       (lambda (root module-root source view)
         (write-file (path-expand "config.ss" module-root) "(def Greeting (error \"must not initialize\")) (export Greeting)")
         (let (prepared (poo-flow-prepare-module-publication source))
           ((.get prepared admit-current))
           (write-file (path-expand "config.ss" module-root) "(def Greeting \"changed\") (export Greeting)")
           (check-exception (poo-flow-write-module-publication prepared (path-expand "stale/interface.ss" root)) error?)
           (check-equal? (module-source-type (path-expand "stale/interface.ss" root)) #f)))))
    (poo-flow-test-case "init changes invalidate a prepared compiler input held by the caller"
      (with-publication-source
       (lambda (root module-root source view)
         (let ((prepared ((.get view prepare-publication) 'custom/example))
               (output (path-expand "stale-selection/interface.ss" root)))
           (write-file (path-expand "init.ss" root)
                       "(poo-flow! mode: auto source: \"./modules\" :custom (example disable: #t))")
           (check-exception (poo-flow-write-module-publication prepared output) error?)
           (check-equal? (module-source-type output) #f)))))
    (poo-flow-test-case "package source edits and disabled Modules refuse compiler preparation"
      (with-publication-source
       (lambda (root module-root source view)
         (let ((prepared ((.get view prepare-publication) 'custom/example))
               (package (path-expand "gerbil.pkg" root)))
           (write-file package (string-append (module-source-read package) "\n; changed generation\n"))
           (check-exception ((.get prepared admit-current)) error?))
         (write-file (path-expand "init.ss" root)
                     "(poo-flow! mode: auto source: \"./modules\" :custom (example disable: #t))")
         (let (disabled (poo-flow-load-modules (path-expand "modules" root)))
           (check-exception ((.get disabled prepare-publication) 'custom/example) error?)))))
    (poo-flow-test-case "macro errors retain the original included interface location"
      (with-publication-source
       (lambda (root module-root source view)
         (write-file (path-expand "interface.ss" module-root)
           "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o greeting:)) features: (.o))")
         (let* ((prepared (poo-flow-prepare-module-publication source))
                (wrapper (path-expand "invalid/interface.ss" root)))
           (poo-flow-write-module-publication prepared wrapper)
           (let (message (exception-message (lambda () (core-import-module wrapper))))
             (check-equal? (if (string-contains message (path-expand "interface.ss" module-root)) #t #f) #t))))))
    (poo-flow-test-case "duplicate fields, inherited dependencies and hand-written link wrappers are rejected"
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
