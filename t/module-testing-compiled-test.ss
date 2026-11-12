;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Narrow runtime compiler/import qualification, not a build or test runner.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :tao3k/yuanxu/ops/objects ProcessScript.)
        (only-in :tao3k/yuanxu/observability/testing-script TestingScript.)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint)
        (only-in :tao3k/yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in :tao3k/yuanxu/module-system/building/test-projection module-test-file-source)
        "./qualification/module-testing/fixtures.ss")
(export module-testing-compiled-test)
(def repository (path-expand ".." (path-directory (this-source-file))))
(def (write-forms path forms)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (for-each (cut pretty-print <> port) forms))))
(def module-testing-compiled-test
  (test-suite "Compiled init namespace across module boundaries"
    (yuanxu-test-case "compiled only-in and rename-in retain identity, laziness and guards"
      (with-yuanxu-fixture (fixture (compiled-selection-fixture repository))
        (prepare-module-selection! fixture 'json-schema)
        (yuanxu-test-checkpoint 'selection-prepared)
        (def root (.get fixture root))
        (def state (.get fixture state))
        (def inherited (string-join (load-path) ":"))
        (.def (ConsumerBuild @ ProcessScript.)
          command: '("gerbil" "-:max-heap=2G,debug=q" "build")
          directory: root
          environment: (.o GERBIL_PATH: state GERBIL_LOADPATH: inherited)
          timeout: 60 idle-timeout: 60 check-status: #f)
        (def prepared (.call ConsumerBuild .run))
        (unless (zero? (.get prepared status))
          (error "consumer package build failed" (.get prepared status) (.get prepared output)))
        (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" state)) #f)
        (check-equal? (file-exists? (path-expand "module-system" root)) #f)
        (yuanxu-test-checkpoint 'consumer-runtime-build-complete)
        (def lib (path-expand "lib" state))
        (def compiled-init (path-expand "compiled-namespace-client/init.ssi" lib))
        (def directory (path-expand "compiled-bindings" root))
        (def test-file (path-expand "t/qualification/module-testing/compiled-test.ss" root))
        (write-forms (path-expand "only.ss" directory)
          `((import :clan/poo/object (only-in ,compiled-init compiled-namespace-client.init.exports))
            (export namespace atomic)
            (def (namespace) (.get compiled-namespace-client.init.exports modules))
            (def (atomic) (.call (.get compiled-namespace-client.init.exports tests) .select '(json-schema)))))
        (write-forms (path-expand "renamed.ss" directory)
          `((import :clan/poo/object
                    (rename-in (only-in ,compiled-init compiled-namespace-client.init.exports)
                               (compiled-namespace-client.init.exports Modules)))
            (export namespace atomic)
            (def (atomic) (.call (.get Modules tests) .select '(json-schema)))
            (def (namespace)
              (let ((init-modules-getter 'caller-binding)) (.get Modules modules)))))
        (write-forms (path-expand "readonly.ss" directory)
          `((import (only-in ,compiled-init compiled-namespace-client.init.exports))
            (set! compiled-namespace-client.init.exports #f)))
        (copy-file
          (path-expand "t/qualification/module-testing/compiled-test.ss" repository)
          test-file)
        (.def (Compiler @ ProcessScript.)
          command: (list "gerbil" "-:max-heap=2G,debug=q" "env" "gxc" "-d" lib)
          directory: root
          environment: (.o GERBIL_PATH: state
                           GERBIL_LOADPATH:
                           (string-append lib ":" root ":" inherited))
          timeout: 60
          check-status: #f)
        (for-each
          (lambda (source)
            (def receipt (.call Compiler .run source))
            (unless (and (zero? (.get receipt status))
                         (not (string-contains (.get receipt output) "*** ERROR")))
              (error "focused runtime compilation failed" source
                     (.get receipt status) (.get receipt output)))
            (yuanxu-test-checkpoint (string->symbol source)))
          ;; The consumer build owns init; Core and its prelude are installed
          ;; dependencies. Compile only the explicit cross-module imports.
          '("compiled-bindings/only.ss" "compiled-bindings/renamed.ss"))
        (def refusal (.call Compiler .run "compiled-bindings/readonly.ss"))
        (check-equal? (zero? (.get refusal status)) #f)
        (check-equal? (and (string-contains (.get refusal output) "Bad syntax")
                          (string-contains (.get refusal output) "set!") #t) #t)
        (check-equal? (file-exists? (path-expand "compiled-namespace-client/compiled-bindings/readonly.o1" lib)) #f)
        (yuanxu-test-checkpoint 'readonly-compilation-refused)
        ;; The production library build is separate from the selected test
        ;; publication. Prepare the latter through its init-owned declaration,
        ;; before starting a consumer which deliberately cannot repair support.
        (def support-directory (path-expand "test-support" root))
        (create-directory support-directory)
        ;; gerbil build requires an ordinary package at its working directory.
        ;; The entry still consumes the parent init's source and output prefix.
        (write-forms (path-expand "gerbil.pkg" support-directory)
          '((package: yuanxu-compiled-test-support prelude: :gerbil/core)))
        (copy-file (path-expand "t/qualification/module-testing/build.ss" repository)
                   (path-expand "build.ss" support-directory))
        (.def (SupportBuild @ ProcessScript.)
          command: '("gerbil" "-:max-heap=2G,debug=q" "build")
          directory: support-directory
          environment: (.o GERBIL_PATH: state
                           GERBIL_LOADPATH: (string-append lib ":" root ":" inherited))
          timeout: 60)
        (.call SupportBuild .run)
        (yuanxu-test-checkpoint 'selected-test-support-published)
        (for-each
          (lambda (name)
            (for-each
              (lambda (extension)
                (check-equal? (file-exists? (path-expand (string-append name extension) lib)) #t))
              '(".ssi" ".o1")))
          '("compiled-namespace-client/init" "compiled-namespace-client/compiled-bindings/only" "compiled-namespace-client/compiled-bindings/renamed"))
        ;; These consumers cannot be imported from their source files below.
        (delete-file (path-expand "only.ss" directory))
        (delete-file (path-expand "renamed.ss" directory))
        (.def (CompiledChecks @ TestingScript.)
          source: (module-test-file-source (list test-file))
          directory: root
          environment: =>.+
          (.o GERBIL_PATH: state
              GERBIL_LOADPATH: (string-append lib ":" root ":" inherited))
          timeout: 60)
        (.call CompiledChecks .run)))))
