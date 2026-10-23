;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export module-configuration-build-test)
(def (assert name value)
  (unless value (error "assertion failed" name))
  (displayln "ASSERT-OK " name) (force-output))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (exception)
      (and (pregexp-match pattern (call-with-output-string (cut display-exception exception <>))) #t))
    (lambda () (thunk) #f)))
(def (shell root id configuration requirements build?)
  (let (owner (path-expand (string-append "modules/" id) root))
    (write-source (path-expand "types.ss" owner)
      "(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)) (def Scope (yuanxu-predicate-contract 'scope object? (lambda (_v _c) '()))) (export Scope)")
    (write-source (path-expand "objects.ss" owner)
      "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
    (write-source (path-expand "config.ss" owner) configuration)
    (write-source (path-expand "interface.ss" owner)
      (string-append "(.def Published identity: '" id " core: (.o requires: " requirements
        " scope-contract: Scope exports: (.o config: Config)"
        (if build? " configuration-build: Build" "") ") features: (.o))"))
    owner))
(def (with-fixture test)
  (call-with-temporary-directory "configuration-build"
    (lambda (root)
      (write-source (path-expand "gerbil.pkg" root)
        (string-append "(package: " (symbol->string (gensym 'configuration-build-)) ")"))
      (let ((builder (shell root "tools/builder" "(def Config (.o value: 'tool))" "(.o)" #t))
            (requirement "(.o Tool: (.o module-id: 'tools/builder contract: Scope))"))
        (shell root "app/one" "(def Config (.o value: 1 cold: (error \"unused config branch\")))" requirement #f)
        (shell root "app/two" "(def Config (.o value: 2))" requirement #f)
        (write-source (path-expand "build.ss" builder)
          (string-append
            "(import (only-in :yuanxu/module-system/building/configuration-source yuanxu-configuration-source)) "
            "(call-with-output-file (list path: "
            (call-with-output-string (cut write (path-expand "build-count" root) <>))
            " append: #t) (lambda (port) (display \"x\" port))) "
            "(def Build (.o kind: 'module/external-package identity: 'probe .prepare: "
            "(lambda (root current! publication) "
            "(let (input (yuanxu-configuration-source (path-expand \"config.ss\" root) 'Config current! role-sources: (.get publication role-sources))) "
            "(.o identity: 'probe configuration: (.get input value) source-inputs: (.get input source-inputs) input-files: '() admit-current: (.get input admit-current) .realize: (lambda (_directory _current!) (error \"unit test must not realize\")))))))"))
        (test root builder)))))
(def module-configuration-build-test
  (test-suite "Dependency-selected configuration build contributions"
    (yuanxu-test-case "one upstream contribution binds two final consumer configs"
      (with-fixture
        (lambda (root _builder)
          (let (init (path-expand "init.ss" root))
            (write-source init "(yuanxu! mode: explicit :tools (builder) :app (one) (two))")
            (let* ((view (yuanxu-load-modules init))
                   (_selected (.get view selected-graph)))
              (assert 'selection-keeps-build-deferred (not (file-exists? (path-expand "build-count" root))))
              (assert 'ordinary-config-before-build (= (.get view modules app one config value) 1))
              (assert 'runtime-link-keeps-build-deferred (not (file-exists? (path-expand "build-count" root))))
              (let* ((graph (.get view build-graph))
                     (_compiler (begin
                                  (.call graph compiler-current)
                                  (assert 'compiler-keeps-operational-build-deferred
                                    (not (file-exists? (path-expand "build-count" root))))))
                     (requests (.get graph external-packages))
                     (one (find (lambda (r) (eq? (.get r configuration-owner) 'app/one)) requests))
                     (two (find (lambda (r) (eq? (.get r configuration-owner) 'app/two)) requests)))
                (assert 'both-consumers-prepared (= (length requests) 2))
                (assert 'one-final-config (= (.get one configuration value) 1))
                (assert 'two-final-config (= (.get two configuration value) 2))
                (assert 'consumer-qualified-identities (not (eq? (.get one identity) (.get two identity))))
                (assert 'one-upstream-build-evaluation (equal? (module-source-read (path-expand "build-count" root)) "x"))
                (assert 'source-owner-preserved (eq? (.get one build-owner) 'tools/builder))
                (assert 'dependency-alias-preserved (eq? (.get one dependency-alias) 'Tool))
                (assert 'consumer-needs-no-build (not (file-exists? (path-expand "modules/app/one/build.ss" root))))
                (assert 'ordinary-config-after-cached-build (= (.get view modules app one config value) 1))
                (write-source (path-expand "modules/app/one/config.ss" root) "(def Config (.o value: 3))")
                (assert 'changed-config-refuses-old-graph
                  (rejects? "stale|refused|changed" (lambda () ((.get graph admit-current)))))
                (assert 'old-config-cache-remains-own-value (= (.get one configuration value) 1))))))))
    (yuanxu-test-case "an unused builder never evaluates its contribution"
      (with-fixture
        (lambda (root builder)
          (write-source (path-expand "build.ss" builder) "(error \"unused construction capability\")")
          (write-source (path-expand "init.ss" root) "(yuanxu! mode: explicit :tools (builder))")
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'unused-builder-has-no-package (null? (.get view build-graph external-packages)))
            (assert 'unused-builder-kept-lazy (not (file-exists? (path-expand "build-count" root))))))))
    (yuanxu-test-case "disabled required builder rejects before any build effect"
      (with-fixture
        (lambda (root _builder)
          (write-source (path-expand "init.ss" root) "(yuanxu! mode: explicit :app (one) :tools (builder disable: #t))")
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'disabled-required-builder-rejected
              (rejects? "required module disabled" (lambda () (.get view build-graph))))
            (assert 'denial-has-no-build-effect (not (file-exists? (path-expand "build-count" root))))))))))
