;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander core-import-module
                 current-expander-context make-top-context)
        (only-in :yuanxu/module-system/source/preparation yuanxu-write-module-publication
                 yuanxu-prepare-module-retained-source call-with-module-compiler-inputs module-compiler-source-input)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read)
        (only-in :yuanxu/module-system/building/configuration-source yuanxu-configuration-source))
(export module-build-role-test)
(def (assert name value)
  (unless value (error "assertion failed" name))
  (displayln "ASSERT-OK " name) (force-output))
(def (rejects? text thunk)
  (with-catch (lambda (e)
                (def message (call-with-output-string (cut display-exception e <>)))
                (def matched? (and (pregexp-match text message) #t))
                (unless matched? (display "UNEXPECTED-REJECTION ") (display message) (force-output))
                matched?)
    (lambda () (thunk) #f)))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (fixture root build)
  (let ((owner (path-expand "modules/app/example" root)))
    (write-source (path-expand "gerbil.pkg" root)
      (string-append "(package: " (symbol->string (gensym 'build-role-)) ")"))
    (write-source (path-expand "init.ss" root)
      "(yuanxu! mode: explicit source: \"./modules\" :app (example) :unused (bomb disable: #t))")
    (write-source (path-expand "types.ss" owner)
      "(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)) (def Scope (yuanxu-predicate-contract 'scope object? (lambda (_v _c) '()))) (export Scope)")
    (write-source (path-expand "objects.ss" owner)
      "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
    (write-source (path-expand "config.ss" owner)
      "(def Config (.o value: 42))")
    (write-source (path-expand "interface.ss" owner)
      "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config forbidden: Build) projections: (list Build)) features: (.o))")
    (write-source (path-expand "build.ss" owner) build)
    (write-source (path-expand "modules/unused/bomb/interface.ss" root) "((invalid disabled interface")
    (write-source (path-expand "modules/unused/bomb/build.ss" root) "((invalid disabled build")
    (write-source (path-expand "modules/unused/unselected/interface.ss" root) "((invalid unselected interface")
    (write-source (path-expand "modules/unused/unselected/build.ss" root) "((invalid unselected build")
    owner))
(def module-build-role-test
  (test-suite "module-build-role-test"
    (yuanxu-test-case "selected compiler sources survive native timestamp path removal only inside their owner"
      (call-with-temporary-directory "module-compiler-owned-source"
        (lambda (root)
          (def owner (fixture root "(def Build (.o kind: 'module/build roots: '()))"))
          (def shared (path-expand "modules/shared.ss" root))
          (write-source shared "(def source-answer 42) (export source-answer)")
          (call-with-output-file (list path: (path-expand "types.ss" owner) append: #t)
            (cut display "\n(import ../../shared) (export source-answer)" <>))
          (write-source (path-expand "config.ss" owner) "(import ../../shared) (def Config (.o value: source-answer))")
          (def saved (load-path))
          (dynamic-wind
            (lambda () (add-load-path! root))
            (lambda ()
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (def scope (.get view modules app example))
              (check-equal? (.get scope config value) 42)
              (def prepared-input (yuanxu-prepare-module-retained-source shared void))
              (def entries (list (.o path: shared input: prepared-input)))
              (def without-root (filter (lambda (p) (not (equal? (path-normalize p) (path-normalize root)))) (load-path)))
              (call-with-module-compiler-inputs entries
                (lambda ()
                  (set-load-path! without-root)
                  (check-equal? (eq? (module-compiler-source-input shared) prepared-input) #t)
                  ((.get view admit-current))
                  (check-equal? (.get scope config value) 42)))
              (check-equal? (module-compiler-source-input shared) #f)
              (assert 'ambient-source-replacement-refuses-after-consumer
                (rejects? "source.*identity|source.*changed|scope.*refused"
                  (lambda () ((.get view admit-current))))))
            (lambda () (set-load-path! saved))))))
    (yuanxu-test-case "compiler source pin rechecks bytes and never enrolls an unselected source"
      (call-with-temporary-directory "module-compiler-source-drift"
        (lambda (root)
          (fixture root "(def Build (.o kind: 'module/build roots: '()))")
          (def shared (path-expand "modules/shared.ss" root))
          (def foreign (path-expand "foreign/shared.ss" root))
          (write-source shared "(def value 42) (export value)")
          (def prepared-input (yuanxu-prepare-module-retained-source shared void))
          (write-source foreign (string-append "package: "
            (path-strip-trailing-directory-separator
              (path-directory (symbol->string (.get prepared-input compiler-identity))))
            "\n(error \"unselected source executed\") (def value 99) (export value)"))
          (def foreign-input (yuanxu-prepare-module-retained-source foreign void))
          (check-equal? (.get foreign-input compiler-identity) (.get prepared-input compiler-identity))
          (call-with-module-compiler-inputs (list (.o path: shared input: prepared-input))
            (lambda ()
              (check-equal? (module-compiler-source-input foreign) #f)
              (write-source shared "(def value 43) (export value)")
              (check-exception (module-compiler-source-input shared) error?)))
          (check-equal? (module-compiler-source-input shared) #f))))
    (yuanxu-test-case "public imports inherit explicit options from later selected Modules"
      (call-with-temporary-directory "module-public-library-options"
        (lambda (root)
          (def owner (fixture root
            "(def Build (.o kind: 'module/build roots: '() library-roots: '(\"public\")))"))
          (def later (path-expand "modules/app/later" root))
          (for-each (lambda (role)
                      (write-source (path-expand role later)
                        (module-source-read (path-expand role owner))))
                    '("types.ss" "objects.ss" "config.ss"))
          (write-source (path-expand "helper.ss" later) "(def value 42) (export value)")
          (write-source (path-expand "build.ss" later)
            "(def Build (.o kind: 'module/build roots: '((gxc: \"helper\" \"-O\"))))")
          (write-source (path-expand "interface.ss" later)
            "(.def Later identity: 'app/later core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (write-source (path-expand "init.ss" root)
            "(yuanxu! mode: explicit source: \"./modules\" :app (example) (later))")
          (write-source (path-expand "public.ss" root)
            "(import ./modules/app/later/helper) (export (import: ./modules/app/later/helper))")
          (add-load-path! root)
          (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
          (def helper (filter (lambda (entry)
                                (equal? (path-normalize (.get entry path))
                                        (path-normalize (path-expand "helper.ss" later))))
                              (.get graph entries)))
          (check-equal? (length helper) 1)
          (check-equal? (.get (car helper) options) '("-O")))))
    (yuanxu-test-case "Module public entries use the native import graph without runtime execution"
      (call-with-temporary-directory "module-public-library-entries"
        (lambda (root)
          (def owner (fixture root
            "(def Build (.o kind: 'module/build roots: '() library-roots: '(\"public\")))"))
          (add-load-path! root)
          (write-source (path-expand "service.ss" owner)
            "(error \"public source runtime must not execute\") (def answer 42) (export answer)")
          (write-source (path-expand "public.ss" root)
            "(import ./modules/app/example/service) (export (import: ./modules/app/example/service))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def graph (.get view build-graph))
          (def paths (map (cut .get <> path) (.get graph entries)))
          (assert 'public-facade-enrolled (member (path-normalize (path-expand "public.ss" root)) (map path-normalize paths)))
          (assert 'native-private-dependency-enrolled (member (path-normalize (path-expand "service.ss" owner)) (map path-normalize paths)))
          (call-with-output-file (list path: (path-expand "service.ss" owner) append: #t)
            (cut display "\n;; changed actual imported source\n" <>))
          (check-exception ((.get graph compiler-current)) error?))))
    (yuanxu-test-case "Module public entries reject package escapes and missing sources"
      (for-each
        (lambda (entry)
          (call-with-temporary-directory "module-public-library-denied"
            (lambda (root)
              (fixture root (string-append
                "(def Build (.o kind: 'module/build roots: '() library-roots: '("
                (object->string entry) ")))"))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (check-exception (.get view build-graph) error?))))
        '("../escape.ss" "missing.ss")))
    (yuanxu-test-case "Module public entries reject symlinks, foreign identities and malformed domains"
      (for-each
        (lambda (kind)
          (call-with-temporary-directory "module-public-library-source-boundary"
            (lambda (root)
              (fixture root
                (if (eq? kind 'malformed)
                  "(def Build (.o kind: 'module/build roots: '() library-roots: '(42)))"
                  "(def Build (.o kind: 'module/build roots: '() library-roots: '(\"public\")))"))
              (case kind
                ((foreign) (write-source (path-expand "public.ss" root)
                             "package: other-native-package (def value 42) (export value)"))
                ((symlink)
                 (write-source (path-expand "target.ss" root) "(def value 42) (export value)")
                 (create-symbolic-link (path-expand "target.ss" root) (path-expand "public.ss" root))))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (check-exception (.get view build-graph) error?))))
        '(symlink foreign malformed)))
    (yuanxu-test-case "private projections preserve native relative-symbol imports"
      (call-with-temporary-directory "module-native-relative-import"
        (lambda (root)
          (def owner (fixture root "(def Build (.o kind: 'module/build roots: '()))"))
          (add-load-path! root)
          (write-source (path-expand "shared.ss" owner) "(def answer 42) (export answer)")
          (write-source (path-expand "private/entry.ss" owner)
            "(import (only-in ../shared answer)) (export answer)")
          (write-source (path-expand "objects.ss" owner)
            "(import :clan/poo/object (only-in ./private/entry answer)) (.def Defaults value: answer) (export Defaults)")
          (write-source (path-expand "interface.ss" owner)
            "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (check-equal? (.get view modules app example value) 42)
          (def graph (.get view build-graph))
          (assert 'native-relative-import-build-graph (object? graph))
          ;; The projection must keep the actual helper in its currentness closure.
          (call-with-output-file (list path: (path-expand "shared.ss" owner) append: #t)
            (cut display "\n;; changed imported source\n" <>))
          (check-exception ((.get view admit-current)) error?))))
    (yuanxu-test-case "original interface compiler gets the lazy phase-bound Build binding"
      (call-with-temporary-directory "module-raw-build-binding"
        (lambda (root)
          (def marker (path-expand "build-forced" root))
          (def owner
            (fixture root
              (string-append "(def Build (begin (call-with-output-file "
                (call-with-output-string (cut write marker <>))
                " (lambda (p) (display \"wrong-phase\" p))) (.o kind: 'module/build roots: '())))")))
          ;; An ordinary compiler has no reader-created publication wrapper.
          ;; Explicit role imports are valid source syntax and do not import Build.
          (write-source (path-expand "config.ss" owner)
            "(import :clan/poo/object) (def Config (.o value: 42)) (export Config)")
          (write-source (path-expand "interface.ss" owner)
            "(import (except-in :clan/poo/object .def) (only-in :yuanxu/module-system/source/declaration .def)) (.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config) configuration-build: Build) features: (.o))")
          (parameterize ((current-expander-context (make-top-context)))
            (core-import-module (path-expand "interface.ss" owner)))
          (assert 'raw-compiler-binds-build-without-executing-it (not (file-exists? marker))))))
    (yuanxu-test-case "configuration cleanup does not import an unused related role"
      (call-with-temporary-directory "configuration-unused-role"
        (lambda (root)
          (def owner (fixture root "(def Build (.o kind: 'module/build roots: '()))"))
          (write-source (path-expand "objects.ss" owner)
            "(begin-syntax (error \"unused related role expanded\")) (error \"unused related role evaluated\")")
          (write-source (path-expand "config.ss" owner)
            "(import (only-in :clan/poo/object .o)) (def Config (.o value: 42))")
          (def config
            (yuanxu-configuration-source (path-expand "config.ss" owner) 'Config void
              role-sources: (list (path-expand "objects.ss" owner))))
          (check-equal? (.get config value value) 42)
          (check-equal? (.get config value value) 42))))
    (yuanxu-test-case "Build is lazy, phase-bound and owner-scoped"
      (call-with-temporary-directory "module-build-role"
        (lambda (root)
          (let* ((marker (path-expand "build-forced" root))
                 (owner (fixture root
                   (string-append "prelude: :gerbil/core\n(def Build (begin (call-with-output-file "
                     (call-with-output-string (cut write marker <>))
                     " (lambda (p) (display \"once\" p))) (.o kind: 'module/build roots: '())))")))
                 (view (yuanxu-load-modules (path-expand "init.ss" root)))
                 (scope (.get view modules app example)))
            (assert 'selection-does-not-run-build (not (file-exists? marker)))
            (assert 'ordinary-scope-still-works (= (.get scope config value) 42))
            (assert 'runtime-build-denied-before-cache
              (rejects? "build-publication phase" (lambda () (.get scope forbidden))))
            (let ((prepared ((.get view prepare-publication) 'app/example))
                  (wrapper (path-expand "compiled/interface.ss" root)))
              (yuanxu-write-module-publication prepared wrapper)
              (parameterize ((current-expander-context (make-top-context)))
                (core-import-module wrapper))
              (assert 'ordinary-compiler-expansion-does-not-run-build
                (not (file-exists? marker))))
            (let (config (yuanxu-configuration-source (path-expand "config.ss" owner) 'Config void
                            role-sources: (list (path-expand "build.ss" owner))))
              (assert 'config-evaluation-excludes-build (= (.get config value value) 42)))
            (assert 'config-did-not-force-build (not (file-exists? marker)))
            (let (graph (.get view build-graph))
              (assert 'graph-access-reuses-native-cache (eq? graph (.get view build-graph)))
              (assert 'build-evaluated-on-graph-demand (equal? (module-source-read marker) "once"))
              (assert 'build-not-a-runtime-compiler-root
                (not (find (lambda (entry) (equal? (path-strip-directory (.get entry path)) "build.ss")) (.get graph entries))))
              (assert 'build-bytes-in-currentness
                (find (lambda (row)
                        (equal? (path-normalize (car row))
                                (path-normalize (path-expand "build.ss" owner))))
                      (.get graph source-inputs))))
            (assert 'runtime-build-denied-after-cache
              (rejects? "build-publication phase" (lambda () (.get scope forbidden))))
            (write-source (path-expand "build.ss" owner) "(def Build (error \"changed\"))")
            (assert 'build-mutation-rejects-old-generation
              (rejects? "compiler tool source changed; use a fresh reader"
                (lambda () ((.get view admit-current)))))))))
    (yuanxu-test-case "Build cannot reload root selection through an alias"
      (call-with-temporary-directory "module-build-reentry"
        (lambda (root)
          (fixture root
            (string-append
              "(import (only-in :yuanxu/module-system/interface yuanxu-load-modules)) "
              "(def reload yuanxu-load-modules) (def Build (reload "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) "))"))
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'root-reentry-denied
              (rejects? "cannot reload the root" (lambda () (.get view build-graph))))))))
    (yuanxu-test-case "Absent Build role is observed and cannot be added to an old generation"
      (call-with-temporary-directory "module-build-absence"
        (lambda (root)
          (let (owner (fixture root "(def Build (.o kind: 'module/build roots: '()))"))
            (delete-file (path-expand "build.ss" owner))
            (write-source (path-expand "interface.ss" owner)
              "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config)) features: (.o))")
            (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
              (.get view build-graph)
              (write-source (path-expand "build.ss" owner) "(def Build (.o kind: 'module/build roots: '()))")
              (assert 'new-build-role-invalidates-old-generation
                (rejects? "stale prepared Module publication"
                (lambda () ((.get view admit-current))))))))))
    (yuanxu-test-case "Build imports cannot escape to the root init source"
      (call-with-temporary-directory "module-build-import"
        (lambda (root)
          (fixture root
            (string-append "(import "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) ") (def Build (.o))"))
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'root-init-source-import-denied
              (rejects? "admitted role|prebuilt library|owner" (lambda () (.get view build-graph))))))))))
