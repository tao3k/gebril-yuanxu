;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Import closure, not a directory-scale surrogate or compiled-cache test.
(import "./qualification/module-init/fixture.ss" :std/test
        (only-in :gerbil/runtime/error RuntimeException? RuntimeException-exception)
        (only-in :clan/poo/object .o .get .slot? .all-slots .ref/cached)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :gerbil/expander current-expander-context make-top-context
                 eval-syntax core-import-module expander-context-id)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/observability/testing-case yuanxu-test-observe))
(export module-init-import-test)
(def Workspace
  (.o .acquire: (lambda ()
                 (let (root (make-temporary-file-name "init-import-"))
                   (create-directory root) root))
      .release: (lambda (root)
                  (clear-temporary-file! root)
                  (check-equal? (file-exists? root) #f))))
(def module-init-import-test
  (test-suite "Init import owns no eager Reader or build execution closure"
    (yuanxu-test-fixture "native init import defers missing source and execution owners"
      (root Workspace)
      (def init (path-expand "init.ss" root))
      (call-with-output-file (path-expand "gerbil.pkg" root)
        (lambda (out) (write (list 'package: (symbol->string (gensym 'init-import-))) out)))
      ;; Deliberately absent module root: importing a declaration is not demand.
      (call-with-output-file init
        (lambda (out)
          (pretty-print '(import :yuanxu/module-system/selection/init-syntax) out)
          (pretty-print '(yuanxu! source: "./modules" mode: explicit (missing)) out)))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax '(import (only-in :clan/poo/object .get)))
        (import-fixture-init! init)
        (def contexts '())
        (for-each-build-module (core-import-module init)
          (lambda (context) (set! contexts (cons (expander-context-id context) contexts))))
        (yuanxu-test-observe 'init-import-contexts (length contexts))
        (for-each
          (lambda (identity) (check-equal? (and (memq identity contexts) #t) #f))
          '(yuanxu/module-system/source/reader
            yuanxu/module-system/source/link
            yuanxu/module-system/building/build-projection
            yuanxu/module-system/building/artifacts
            yuanxu/observability/testing-script))
        (def tests (eval-syntax '(.get FixtureExports tests)))
        (check-equal? (.slot? tests '.run) #t)
        (check-equal? (.ref/cached tests 'execution) #f)
        (check-equal? (.ref/cached tests 'spec) #f)
        (create-directory (path-expand "modules" root))
        ;; The first explicit namespace demand must fail, not publish an empty
        ;; successful selection or hide the missing source behind the promise.
        (check-exception (eval-syntax '(.get FixtureExports modules)) error?)))
    (yuanxu-test-fixture "namespace enumeration does not construct a publication Reader"
      (root Workspace)
      (def directory (path-expand "modules/example" root))
      (create-directory* directory)
      (call-with-output-file (path-expand "gerbil.pkg" root)
        (lambda (out) (write (list 'package: (symbol->string (gensym 'init-names-))) out)))
      (for-each
        (lambda (name)
          (call-with-output-file (path-expand name directory)
            (lambda (out) (write '(error "unrequested role evaluated") out))))
        '("types.ss" "objects.ss" "config.ss" "interface.ss"))
      (def init (path-expand "init.ss" root))
      (call-with-output-file init
        (lambda (out)
          (pretty-print '(import :yuanxu/module-system/selection/init-syntax) out)
          (pretty-print '(yuanxu! source: "./modules" mode: auto) out)))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax '(import (only-in :clan/poo/object .get)))
        (import-fixture-init! init)
        (def counts (make-hash-table-eq))
        (def previous (current-module-source-observer))
        (def (observe key amount)
          (when (symbol? key) (hash-update! counts key (cut + <> amount) 0))
          (when previous (previous key amount)))
        (parameterize ((current-module-source-observer observe))
          (def modules (eval-syntax '(.get FixtureExports modules)))
          (check-equal? (.all-slots modules) '(example))
          (check-equal? (eq? modules (eval-syntax '(.get FixtureExports modules))) #t)
          (def example (.get modules example))
          (check-equal? (.ref/cached example 'scope) #f)
          (check-equal? (.ref/cached example 'tests) #f)
          (for-each
            (lambda (key) (check-equal? (hash-ref counts key 0) 0))
            '(compiler-closure-requests compiler-closure-walks publication-start reader-declaration))
          ;; Even without an interpreter, the namespace remains source-bound.
          (call-with-output-file (list path: init append: #t)
            (lambda (out) (newline out)))
          (check-exception (eval-syntax '(.get FixtureExports modules)) error?))))))

(def qualified-init-import-test
  (test-suite "Source-qualified init exports"
    (yuanxu-test-fixture "native package and module identities own distinct lazy entries"
      (root Workspace)
      (def left (string->symbol (symbol->string (gensym 'contribution-left-))))
      (def right (string->symbol (symbol->string (gensym 'contribution-right-))))
      (def (prepare! package prelude (file "init.ss"))
        (def directory (path-expand (symbol->string package) root))
        (create-directory* directory)
        (call-with-output-file (path-expand "gerbil.pkg" directory)
          (lambda (out) (write `(package: ,package prelude: ,prelude) out)))
        (def path (path-expand file directory))
        (call-with-output-file path
          (lambda (out)
            (pretty-print '(import :yuanxu/module-system/selection/init-syntax) out)
            (pretty-print '(yuanxu! :load-modules "./absent" mode: explicit
                                   rename: Modules (missing)) out)))
        path)
      (def left-path (prepare! left ':tao3k/yuanxu/prelude))
      (def right-path (prepare! right ':gerbil/core))
      ;; A second declaration in the same package needs no init.ss suffix.
      (def selection-path (prepare! left ':tao3k/yuanxu/prelude "selection.ss"))
      (def left-name (string->symbol (string-append (symbol->string left) ".init.exports")))
      (def right-name (string->symbol (string-append (symbol->string right) ".init.exports")))
      (def selection-name (string->symbol (string-append (symbol->string left) ".selection.exports")))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core :clan/poo/object))
        (eval-syntax '(def yuanxu-module-init 'caller-owned))
        ;; Ordinary imports suffice: neither prefix-in nor an alias registry.
        (eval-syntax `(import ,left-path ,right-path ,selection-path))
        (def left-value (eval-syntax left-name))
        (def right-value (eval-syntax right-name))
        (def selection-value (eval-syntax selection-name))
        (check-equal? (eq? left-value right-value) #f)
        (check-equal? (eq? left-value selection-value) #f)
        (check-equal? (eval-syntax 'yuanxu-module-init) 'caller-owned)
        (check-equal? (.ref/cached left-value 'Modules) #f)
        (check-equal? (.ref/cached right-value 'Modules) #f)
        (check-equal? (.ref/cached selection-value 'Modules) #f)
        (check-equal? (.ref/cached (.get left-value tests) 'selected-graph) #f)
        (check-equal? (.ref/cached (.get right-value tests) 'execution) #f)
        (check-equal? (eval-syntax
          `(eq? ,left-name
             (let ((init-exports-value 'caller) (init-modules-getter 'caller)) ,left-name))) #t)
        (eval-syntax `(import (rename-in (only-in ,left-path ,left-name) (,left-name Renamed))))
        (check-equal? (eq? left-value (eval-syntax 'Renamed)) #t)
        (for-each
          (lambda (name)
            (check-exception
              (eval-syntax `(import (only-in ,left-path ,name))) error?))
          '(init.exports init.Modules init.modules yuanxu-module-init))
        (check-exception (eval-syntax `(set! ,left-name #f)) syntax-error?)
        ;; Demand, not import, discovers the deliberately missing directory.
        (check-exception (.get left-value Modules)
          (lambda (failure)
            (and (RuntimeException? failure)
                 (no-such-file-or-directory-exception?
                   (RuntimeException-exception failure)))))))))
(export qualified-init-import-test)
