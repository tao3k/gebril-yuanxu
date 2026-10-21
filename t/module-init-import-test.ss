;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Import closure, not a directory-scale surrogate or compiled-cache test.
(import :std/test
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
        (eval-syntax `(import ,init))
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
        (def tests (eval-syntax 'init.tests))
        (check-equal? (.slot? tests '.run) #t)
        (check-equal? (.ref/cached tests 'execution) #f)
        (check-equal? (.ref/cached tests 'spec) #f)
        (create-directory (path-expand "modules" root))
        ;; The first explicit namespace demand must fail, not publish an empty
        ;; successful selection or hide the missing source behind the promise.
        (check-exception (eval-syntax 'init.modules) error?)))
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
        (eval-syntax `(import ,init))
        (def counts (make-hash-table-eq))
        (def previous (current-module-source-observer))
        (def (observe key amount)
          (when (symbol? key) (hash-update! counts key (cut + <> amount) 0))
          (when previous (previous key amount)))
        (parameterize ((current-module-source-observer observe))
          (def modules (eval-syntax 'init.modules))
          (check-equal? (.all-slots modules) '(example))
          (check-equal? (eq? modules (eval-syntax 'init.modules)) #t)
          (def example (.get modules example))
          (check-equal? (.ref/cached example 'scope) #f)
          (check-equal? (.ref/cached example 'tests) #f)
          (for-each
            (lambda (key) (check-equal? (hash-ref counts key 0) 0))
            '(compiler-closure-requests compiler-closure-walks publication-start reader-declaration))
          ;; Even without an interpreter, the namespace remains source-bound.
          (call-with-output-file (list path: init append: #t)
            (lambda (out) (newline out)))
          (check-exception (eval-syntax 'init.modules) error?))))))
