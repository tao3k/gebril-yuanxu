;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source data and probes only. No dispatcher or test runner.
(import :clan/poo/object
        (only-in :std/io/tempfile clear-temporary-file!)
        "../module-bootstrap/fixtures.ss"
        (only-in "../testing/directory.ss" DirectoryFixture))
(export selection-fixture compiled-selection-fixture)
(def (write-forms path forms)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (for-each (cut pretty-print <> port) forms))))
(def (observe-export datum)
  ;; Preserve the real declaration, dependencies, contracts and export value.
  ;; Only execution of its deferred exports expression writes this probe.
  (cond
    ((not (pair? datum)) datum)
    ((eq? (car datum) 'exports:)
     (cons 'exports:
       (cons `(begin
                (call-with-output-file "json-schema.scope"
                  (lambda (port) (display "scope" port)))
                ,(cadr datum))
             (cddr datum))))
    (else (cons (observe-export (car datum))
                (observe-export (cdr datum))))))
(def (selection-fixture repository)
  (.o .acquire:
      (lambda ()
        (def paths (load-path))
        (def prefix (getenv "GERBIL_PATH" #f))
        (def source (source-build-fixture repository #f))
        (def fixture (.cc source
                         root: (path-normalize (.get source root))
                         state: (path-normalize (.get source state))
                         previous-path: paths previous-prefix: prefix))
        (setenv "GERBIL_PATH" (.get fixture state))
        fixture)
      .release: (lambda (fixture)
                  (dynamic-wind void
                    (lambda ()
                      (clear-temporary-file!
                        (path-normalize (path-expand "../../.." (.get fixture root)))))
                    (lambda ()
                      (set-load-path! (.get fixture previous-path))
                      (setenv "GERBIL_PATH" (.get fixture previous-prefix)))))))

(def (prepare-module-selection! root)
  (def interface (path-expand "modules/json-schema/interface.ss" root))
  (def forms (call-with-input-file interface read-all))
  (write-forms interface (map observe-export forms))
  ;; The selected test must be discovered under its new name.
  (def tests (path-expand "modules/json-schema/tests" root))
  (for-each
    (lambda (file)
      (when (string-suffix? "-test.ss" file)
        (rename-file (path-expand file tests)
                     (path-expand (string-append "discovered-" file) tests))))
    (directory-files tests))
  (create-directory* (path-expand "modules/unselected/tests" root))
  (write-forms (path-expand "modules/unselected/interface.ss" root)
    '((import :clan/poo/object
              (only-in "../json-schema/types.ss" JsonSchemaScopeContract))
      (export Unselected)
      (.def Unselected
        identity: 'unselected
        tags: '(test)
        core: (.o scope-contract: JsonSchemaScopeContract
                  exports: (error "unselected module scope evaluated"))
        features: (.o))))
  (write-forms (path-expand "modules/unselected/tests/atomic-test.ss" root)
    '((error "unselected module test evaluated"))))

(def (compiled-selection-fixture repository)
  (.cc DirectoryFixture
    prefix: "compiled-namespace-client-"
    .prepare:
    (lambda (resource)
      (def root (.get resource root))
      (def state (path-expand ".gerbil" root))
      (create-directory* (path-expand "lib" state))
      (create-directory* (path-expand "t/qualification/module-testing" root))
      (copy-fixture-tree (path-expand "modules/json-schema" repository)
        (path-expand "modules/json-schema" root)
        (lambda (_path file _kind) (not (string-prefix? "." file))))
      (prepare-module-selection! root)
      (write-forms (path-expand "gerbil.pkg" root)
        '((package: compiled-namespace-client prelude: :tao3k/yuanxu/prelude)))
      (write-forms (path-expand "init.ss" root)
        '((yuanxu! :test-dir "./t" source: "./modules" mode: explicit (json-schema))))
      (call-with-output-file (list path: (path-expand "build.ss" root) permissions: #o755)
        (lambda (port)
          (display "#!/usr/bin/env gxi\n" port)
          (for-each (cut pretty-print <> port)
            '((import :clan/poo/object
                      (only-in :std/source this-source-file)
                      (only-in :tao3k/yuanxu/module-system/building/source-closure package-library-spec)
                      (only-in :std/build-script defbuild-script)
                      (only-in "./init.ss" compiled-namespace-client.init.exports))
              (def consumer-spec
                (package-library-spec (path-directory (this-source-file))
                  'compiled-namespace-client '("init.ss")))
              (defbuild-script
                (append (.get compiled-namespace-client.init.exports std-make-spec) consumer-spec))))))
      (.cc resource state: state))))
