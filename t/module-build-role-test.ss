;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander core-import-module
                 current-expander-context make-top-context)
        (only-in :core/module-system/source/preparation poo-flow-write-module-publication)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/module-system/source/admission module-source-read)
        (only-in :core/module-system/building/configuration-source poo-flow-core-configuration-source))
(export module-build-role-test)
(def (assert name value)
  (unless value (error "assertion failed" name))
  (displayln "ASSERT-OK " name) (force-output))
(def (rejects? text thunk)
  (with-catch (lambda (e) (and (pregexp-match text (call-with-output-string (cut display-exception e <>))) #t))
    (lambda () (thunk) #f)))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (fixture root build)
  (let ((owner (path-expand "modules/app/example" root)))
    (write-source (path-expand "gerbil.pkg" root)
      (string-append "(package: " (symbol->string (gensym 'build-role-)) ")"))
    (write-source (path-expand "init.ss" root)
      "(poo-flow! mode: explicit source: \"./modules\" :app (example) :unused (bomb disable: #t))")
    (write-source (path-expand "types.ss" owner)
      "(import :clan/poo/object (only-in :core/types poo-flow-predicate-contract)) (def Scope (poo-flow-predicate-contract 'scope object? (lambda (_v _c) '()))) (export Scope)")
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
    (poo-flow-test-case "Build is lazy, phase-bound and owner-scoped"
      (call-with-temporary-directory "module-build-role"
        (lambda (root)
          (let* ((marker (path-expand "build-forced" root))
                 (owner (fixture root
                   (string-append "prelude: :gerbil/core\n(def Build (begin (call-with-output-file "
                     (call-with-output-string (cut write marker <>))
                     " (lambda (p) (display \"once\" p))) (.o kind: 'module/build roots: '())))")))
                 (view (poo-flow-load-modules (path-expand "init.ss" root)))
                 (scope (.get view modules app example)))
            (assert 'selection-does-not-run-build (not (file-exists? marker)))
            (assert 'ordinary-scope-still-works (= (.get scope config value) 42))
            (assert 'runtime-build-denied-before-cache
              (rejects? "build-publication phase" (lambda () (.get scope forbidden))))
            (let ((prepared ((.get view prepare-publication) 'app/example))
                  (wrapper (path-expand "compiled/interface.ss" root)))
              (poo-flow-write-module-publication prepared wrapper)
              (parameterize ((current-expander-context (make-top-context)))
                (core-import-module wrapper))
              (assert 'ordinary-compiler-expansion-does-not-run-build
                (not (file-exists? marker))))
            (let (config (poo-flow-core-configuration-source (path-expand "config.ss" owner) 'Config void
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
              (rejects? "stale|refused" (lambda () ((.get view admit-current)))))))))
    (poo-flow-test-case "Build cannot reload root selection through an alias"
      (call-with-temporary-directory "module-build-reentry"
        (lambda (root)
          (fixture root
            (string-append
              "(import (only-in :core/module-system/interface poo-flow-load-modules)) "
              "(def reload poo-flow-load-modules) (def Build (reload "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) "))"))
          (let (view (poo-flow-load-modules (path-expand "init.ss" root)))
            (assert 'root-reentry-denied
              (rejects? "cannot reload the root" (lambda () (.get view build-graph))))))))
    (poo-flow-test-case "Absent Build role is observed and cannot be added to an old generation"
      (call-with-temporary-directory "module-build-absence"
        (lambda (root)
          (let (owner (fixture root "(def Build (.o kind: 'module/build roots: '()))"))
            (delete-file (path-expand "build.ss" owner))
            (write-source (path-expand "interface.ss" owner)
              "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config)) features: (.o))")
            (let (view (poo-flow-load-modules (path-expand "init.ss" root)))
              (.get view build-graph)
              (write-source (path-expand "build.ss" owner) "(def Build (.o kind: 'module/build roots: '()))")
              (assert 'new-build-role-invalidates-old-generation
                (rejects? "stale|refused" (lambda () ((.get view admit-current))))))))))
    (poo-flow-test-case "Build imports cannot escape to the root init source"
      (call-with-temporary-directory "module-build-import"
        (lambda (root)
          (fixture root
            (string-append "(import "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) ") (def Build (.o))"))
          (let (view (poo-flow-load-modules (path-expand "init.ss" root)))
            (assert 'root-init-source-import-denied
              (rejects? "admitted role|prebuilt library|owner" (lambda () (.get view build-graph))))))))))
