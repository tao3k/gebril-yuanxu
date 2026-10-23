;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context
                 core-resolve-library-module-path))
(export module-build-source-package-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def module-build-source-package-test
  (if root
    (test-suite "Build-owned source package registration"
      (test-case "wrong package refuses registration without changing search order"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core))
          (eval-syntax '(import (only-in :clan/poo/object .get)))
          (eval-syntax `(import
                         (only-in ,(path-expand "module-system/building/source-package.ss" root)
                                  register-module-build-source!)))
          (def register! (eval-syntax 'register-module-build-source!))
          (call-with-temporary-directory "wrong-build-package"
            (lambda (foreign)
              (write-source (path-expand "gerbil.pkg" foreign) "(package: foreign)\n")
              (def before (load-path))
              (check-exception (register! foreign 'yuanxu) error?)
              (check-equal? (load-path) before)))))
      (test-case "build registration precedes init imports and guards tool drift"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core))
          (eval-syntax '(import (only-in :clan/poo/object .get)))
          (eval-syntax `(import
                         (only-in ,(path-expand "module-system/building/source-package.ss" root)
                                  register-yuanxu-build-source!)))
          ((eval-syntax 'register-yuanxu-build-source!) root)
          (eval-syntax `(import
                         (only-in ,(path-expand "init.ss" root) yuanxu.init.exports )))
          (check-equal? (core-resolve-library-module-path ':yuanxu/object-family/syntax)
                        (path-normalize (path-expand "object-family/syntax.ss" root)))
          ;; The Core package prefix must not capture public dependency imports.
          (check-equal? (string-prefix? (path-normalize root)
                           (core-resolve-library-module-path ':clan/poo/object)) #f)
          (def spec (eval-syntax '(.get yuanxu.init.exports std-make-spec)))
          (def current! (eval-syntax '(.get yuanxu.init.exports admit-current)))
          (def retained '("utilities/algorithms" "object-types/contracts" "core-spec"))
          (def targets (spec retained))
          (check-equal? (eq? targets (spec retained)) #t)
          (current!)
          (def path (path-expand "module-system/building/source-package.ss" root))
          (def original (call-with-input-file path read-all-as-string))
          (dynamic-wind
            (lambda () (write-source path (string-append original "\n;; changed registration source\n")))
            (lambda () (check-exception (current!) error?))
            (lambda () (write-source path original))))))
    (test-suite "Build source registration (opt-in)" (void))))
