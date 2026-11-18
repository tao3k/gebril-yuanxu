;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander current-expander-context eval-syntax make-top-context)
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/module-system/building/products current-build-output-directory)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in "./qualification/module-init/fixture.ss" import-fixture-init! with-compiler-progress))
(export module-build-command-test)

(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file path (lambda (port) (display text port))))

(def (write-module root path identity)
  (def owner (path-expand path root))
  (write-source (path-expand "types.ss" owner)
    "(import :clan/poo/object (only-in :clan/poo/type Type.)) (def Scope (.cc Type. identity: 'scope .element?: object?)) (export Scope)")
  (write-source (path-expand "objects.ss" owner)
    "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
  (write-source (path-expand "interface.ss" owner)
    (string-append "(.def Module identity: '" identity
                   " core: (.o scope-contract: Scope exports: Defaults) features: (.o))")))

(def (rejects? message)
  (lambda (error)
    (pregexp-match message (call-with-output-string (cut display-exception error <>)))))

(def module-build-command-test
  (test-suite "Explicit Module and mount compiler command"
    (yuanxu-test-case "one native build consumes the union without changing the default spec"
      (call-with-temporary-directory "module-build-command"
        (lambda (root)
          (def package (symbol->string (gensym 'build-command-)))
          (def init (path-expand "init.ss" root))
          (def entry (path-expand "compile.ss" root))
          (write-source (path-expand "gerbil.pkg" root) (string-append "(package: " package ")"))
          (write-source init
            "(import :tao3k/yuanxu/module-system/selection/init-syntax)
             (yuanxu!
               :load-modules \"./default\" mode: explicit mount: Default
               (main) (blocked disable: #t)
               :load-modules \"./tools\" mode: explicit mount: Tools export: ToolsSource
               :load-modules \"./cold\" mode: explicit mount: Cold export: ColdSource)")
          (write-module root "default/main" "main")
          (write-module root "tools/worker" "worker")
          ;; Importing the CLI or inspecting the default spec must leave both
          ;; export-only windows cold.
          (write-module root "cold/unused" "unused")
          (write-source (path-expand "cold/unused/build.ss" root) "(error \"unexpected build\")")
          (write-source entry
            (string-append
              "(import (only-in :tao3k/yuanxu/module-system/building/build-script yuanxu-compile-main)
                       (only-in \"./init.ss\" " package ".init.exports))
               (def (main . args) (apply yuanxu-compile-main " package ".init.exports args))
               (export main)"))
          (parameterize ((current-expander-context (make-top-context))
                         (current-build-output-directory (path-expand "lib" root)))
            (def exports (import-fixture-init! init))
            (eval-syntax `(import (rename-in (only-in ,entry main) (main compile-main))))
            (def compile (eval-syntax 'compile-main))
            (def default-spec (.get exports std-make-spec))
            (def (product path)
              (file-exists? (path-expand (string-append "lib/" package "/" path "/interface.ssi") root)))
            (check-equal? (product "tools/worker") #f)
            (check-exception (compile "--extra" "main") (rejects? "unknown compile selector"))
            (check-exception (compile "--modules") (rejects? "requires at least one name"))
            (check-exception (compile "--mounts" "Missing") (rejects? "unknown build mount"))
            (check-exception (compile "--modules" "Default/blocked") (rejects? "disabled"))
            (check-exception (compile "--modules" "Default/missing") (rejects? "outside selected"))
            (def input-path (load-path))
            (with-compiler-progress
              (lambda ()
                (compile "--modules" "Tools/worker" "Tools/worker")))
            (check-equal? (load-path) input-path)
            (check-equal? (product "tools/worker") #t)
            (check-equal? (product "default/main") #f)
            (check-equal? (product "cold/unused") #f)
            (check-equal? (.get exports std-make-spec) default-spec)
            (with-compiler-progress
              (lambda ()
                (compile "--modules" "worker" "Tools/worker" "--mounts" "Tools" "Default" "Default")))
            (check-equal? (product "default/main") #t)))))))
