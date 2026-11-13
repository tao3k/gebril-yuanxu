;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :clan/poo/object .get .call .cc)
        (only-in :std/source this-source-file)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context
                 core-resolve-library-module-path))
(export module-build-source-package-test test-setup! test-cleanup!)
;; Source-only registration is a standard Suite, not a nested Harness invocation.
;; The existing Fixture owns a fresh cold snapshot and its cleanup.
(def Fixture (selection-fixture (path-expand ".." (path-directory (this-source-file)))))
(def resource #f)
(def root #f)
(def (test-setup!)
  (set! resource (.call Fixture .acquire))
  (set! root (.get resource root)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource)
      (set! resource #f) (set! root #f))))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def module-build-source-package-test
    (test-suite "Build-owned source package registration"
      (test-case "wrong package refuses registration without changing search order"
        (check-equal? (.get resource cold) #t)
        (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" (.get resource state))) #f)
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core))
          (eval-syntax '(import (only-in :clan/poo/object .get .cc)))
          (eval-syntax `(import
                         (only-in ,(path-expand "module-system/building/source-package.ss" root)
                                  register-module-build-source!)))
          (def register! (eval-syntax 'register-module-build-source!))
          (call-with-temporary-directory "wrong-build-package"
            (lambda (foreign)
              (write-source (path-expand "gerbil.pkg" foreign) "(package: foreign)\n")
              (def before (load-path))
              (check-exception (register! foreign 'tao3k/yuanxu) error?)
              (check-equal? (load-path) before)))))
      (test-case "build registration precedes init imports and guards tool drift"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core))
          (eval-syntax '(import (only-in :clan/poo/object .get .cc)))
          (eval-syntax `(import
                         (only-in ,(path-expand "module-system/building/source-package.ss" root)
                                  register-module-build-source!)))
          ((eval-syntax 'register-module-build-source!) root 'tao3k/yuanxu)
          (eval-syntax `(import
                         (only-in ,(path-expand "init.ss" root) tao3k/yuanxu.init.exports )))
          (check-equal? (core-resolve-library-module-path ':tao3k/yuanxu/object/syntax)
                        (path-normalize (path-expand "object/syntax.ss" root)))
          ;; The Core package prefix must not capture public dependency imports.
          (check-equal? (string-prefix? (path-normalize root)
                           (core-resolve-library-module-path ':clan/poo/object)) #f)
          (def retained '("utilities/algorithms" "types/contracts" "core-spec"))
          (def package (yuanxu-project-source-spec (path-expand "init.ss" root)
                          retained root (path-expand "build.ss" root)))
          (def targets (.get package spec))
          (def current! (.get package admit-current))
          (check-equal? (eq? targets (.get package spec)) #t)
          (current!)
          (def path (path-expand "module-system/building/source-package.ss" root))
          (def original (call-with-input-file path read-all-as-string))
          (dynamic-wind
            (lambda () (write-source path (string-append original "\n;; changed registration source\n")))
            (lambda () (check-exception (current!) error?))
            (lambda () (write-source path original)))))))
