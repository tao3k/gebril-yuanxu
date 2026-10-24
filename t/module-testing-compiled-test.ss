;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Narrow native compiler/import qualification, not a build or test runner.
(import "../init.ss" :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :yuanxu/ops/objects ProcessScript.)
        (only-in :yuanxu/observability/testing-script TestingScript.)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint)
        (only-in :yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in :yuanxu/module-system/building/test-projection module-test-file-source)
        (only-in "./qualification/module-bootstrap/objects.ss" Build)
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
      (with-yuanxu-fixture (fixture (selection-fixture repository))
        (prepare-selection! fixture repository 'json-schema)
        (yuanxu-test-checkpoint 'selection-prepared)
        (def root (.get fixture root))
        (def state (.get fixture state))
        ;; Compile this fixture's own Core through the maintained source build.
        ;; Importing another Core epoch into the parent VM would correctly
        ;; invalidate the reader's captured compiler-tool contexts.
        (def prepared
          (.call (.cc Build 'directory root 'environment (.o GERBIL_PATH: state)) .run "compile"))
        (unless (zero? (.get prepared status))
          (error "fixture source build failed" (.get prepared status) (.get prepared output)))
        (yuanxu-test-checkpoint 'fixture-native-build-complete)
        (def lib (path-expand "lib" state))
        (def compiled-init (path-expand "yuanxu/init.ssi" lib))
        (def directory (path-expand "compiled-bindings" root))
        (def test-file (path-expand "t/qualification/module-testing/compiled-test.ss" root))
        (write-forms (path-expand "only.ss" directory)
          `((import :clan/poo/object (only-in ,compiled-init yuanxu.init.exports))
            (export namespace atomic)
            (def (namespace) (.get yuanxu.init.exports modules))
            (def (atomic) (.get yuanxu.init.exports modules json-schema tests))))
        (write-forms (path-expand "renamed.ss" directory)
          `((import :clan/poo/object
                    (rename-in (only-in ,compiled-init yuanxu.init.exports)
                               (yuanxu.init.exports Modules)))
            (export namespace)
            (def (namespace)
              (let ((init-modules-getter 'caller-binding)) (.get Modules modules)))))
        (write-forms (path-expand "readonly.ss" directory)
          `((import (only-in ,compiled-init yuanxu.init.exports))
            (set! yuanxu.init.exports #f)))
        (copy-file
          (path-expand "t/qualification/module-testing/compiled-test.ss" repository)
          test-file)
        (.def (Compiler @ ProcessScript.)
          command: (list "gerbil" "-:max-heap=2G,debug=q" "env" "gxc" "-d" lib)
          directory: root
          environment: (.o GERBIL_PATH: state
                           GERBIL_LOADPATH:
                           (string-append lib ":" (path-expand ".." root)))
          timeout: 60
          check-status: #f)
        (for-each
          (lambda (source)
            (def receipt (.call Compiler .run source))
            (unless (and (zero? (.get receipt status))
                         (not (string-contains (.get receipt output) "*** ERROR")))
              (error "focused native compilation failed" source
                     (.get receipt status) (.get receipt output)))
            (yuanxu-test-checkpoint (string->symbol source)))
          ;; Build already owns the real prelude target. This gate compiles
          ;; only its explicit init/import consumers, not that language twice.
          '("init.ss" "compiled-bindings/only.ss" "compiled-bindings/renamed.ss"))
        (def refusal (.call Compiler .run "compiled-bindings/readonly.ss"))
        (check-equal? (zero? (.get refusal status)) #f)
        (check-equal? (and (string-contains (.get refusal output) "Bad syntax")
                          (string-contains (.get refusal output) "set!") #t) #t)
        (check-equal? (file-exists? (path-expand "yuanxu/compiled-bindings/readonly.o1" lib)) #f)
        (yuanxu-test-checkpoint 'readonly-compilation-refused)
        (for-each
          (lambda (name)
            (for-each
              (lambda (extension)
                (check-equal? (file-exists? (path-expand (string-append name extension) lib)) #t))
              '(".ssi" ".o1")))
          '("yuanxu/init" "yuanxu/compiled-bindings/only" "yuanxu/compiled-bindings/renamed"))
        ;; These consumers cannot be imported from their source files below.
        (delete-file (path-expand "only.ss" directory))
        (delete-file (path-expand "renamed.ss" directory))
        (.def (CompiledChecks @ TestingScript.)
          source: (module-test-file-source (list test-file))
          directory: root
          environment: =>.+
          (.o GERBIL_PATH: state
              GERBIL_LOADPATH: (string-append lib ":" (path-expand ".." root)))
          timeout: 60)
        (.call CompiledChecks .run)))))
