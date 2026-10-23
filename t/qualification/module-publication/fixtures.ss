;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation shared by publication suites; no test suite is imported.
(import (only-in :clan/poo/object .def .o .get)
        (only-in :std/test check-equal?)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/runtime/loader load-path set-load-path!)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/module-system/source/admission module-source-type)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules))
(export write-file remove-tree with-publication-source domain-entry-count native-import-value exception-message PublicLibraryFixture core-source-root)
(def core-source-root (path-expand "../../.." (path-directory (this-source-file))))

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
         "(import (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract) (only-in :clan/poo/object object?)) (def FixtureContract (yuanxu-predicate-contract 'fixture object? (lambda (_v _c) '()))) (export FixtureContract)")
       (write-file (path-expand "objects.ss" module-root)
         "(import (only-in :clan/poo/object .o)) (def FixtureScope (.o retained: 'upstream)) (export FixtureScope)")
       (write-file (path-expand "config.ss" module-root)
         "(def Greeting \"hello\") (export Greeting)")
       (write-file (path-expand "interface.ss" module-root)
         "(.def Fixture identity: 'custom/example core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o (:: @ FixtureScope) greeting: Greeting)) features: (.o))"))
     (lambda ()
       (let* ((view (yuanxu-load-modules (path-expand "modules" root)))
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

(.def PublicLibraryFixture
  .acquire:
  (lambda ()
    (def fixture-root (make-temporary-file-name "publication-public-library-"))
    (def original-paths (load-path))
    (def package-name (symbol->string (gensym 'publication-library-)))
    (def first-root (path-expand "first" fixture-root))
    (def shadow-root (path-expand "shadow" fixture-root))
    (def relative (string-append package-name "/helper.ss"))
    (with-catch
      (lambda (failure)
        (set-load-path! original-paths)
        (when (file-exists? fixture-root) (remove-tree fixture-root))
        (raise failure))
      (lambda ()
        (for-each
          (lambda (root)
            (write-file (path-expand (string-append package-name "/gerbil.pkg") root)
              (call-with-output-string (cut write (list package: package-name) <>)))
            (write-file (path-expand relative root)
              "(def ExternalValue \"original\") (export ExternalValue)"))
          (list first-root shadow-root))
        (set-load-path! (cons first-root original-paths))
        (.o root: fixture-root path: (path-expand relative first-root)
            shadow: shadow-root paths: original-paths))))
  .release:
  (lambda (resource)
    (set-load-path! (.get resource paths))
    (remove-tree (.get resource root))
    (check-equal? (file-exists? (.get resource root)) #f)))
