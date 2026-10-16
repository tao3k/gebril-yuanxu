;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .def .o .get .ref .slot? object?)
        (only-in :gerbil/expander eval-syntax datum->syntax current-expander-context make-top-context
                 core-import-module core-expand expander-context-id)
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
    (poo-flow-test-case "source preparation does not initialize role values and stale sources refuse output"
      (with-publication-source
       (lambda (root module-root source view)
         (write-file (path-expand "config.ss" module-root) "(def Greeting (error \"must not initialize\")) (export Greeting)")
         (let (prepared (poo-flow-prepare-module-publication source))
           ((.get prepared admit-current))
           (write-file (path-expand "config.ss" module-root) "(def Greeting \"changed\") (export Greeting)")
           (check-exception (poo-flow-write-module-publication prepared (path-expand "stale/interface.ss" root)) error?)
           (check-equal? (module-source-type (path-expand "stale/interface.ss" root)) #f)))))
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
