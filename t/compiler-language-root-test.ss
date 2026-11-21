;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .o .ref)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander import-module expander-context-id)
        (only-in :tao3k/yuanxu/module-system/building/products current-build-output-directory current-build-source-directory)
        (only-in :tao3k/yuanxu/module-system/source/preparation
                 yuanxu-prepare-module-build-source yuanxu-prepare-module-retained-source call-with-module-compiler-inputs))
(export compiler-language-root-test)
(def (write-source file text)
  (call-with-output-file (list path: file truncate: #t) (cut display text <>)))
(def (entry input)
  (.o kind: 'source (input := input) (path := (.ref input 'path))
      (compiler-identity := (.ref input 'compiler-identity)) options: '()))
(def compiler-language-root-test
  (test-suite "Native language entry in a unified compiler view"
    (test-case "a selected native prelude retains its surface import syntax"
      (call-with-temporary-directory "compiler-language-"
        (lambda (directory)
          (write-source (path-expand "gerbil.pkg" directory) "(package: language-fixture)\n")
          (def source (path-expand "value.ss" directory))
          (write-source source
            "prelude: :tao3k/yuanxu/prelude\n(import (only-in :clan/poo/object .o)) (export value) (def value (.o accepted: #t))\n")
          (def language
            (yuanxu-prepare-module-build-source
              (path-expand "../prelude.ss" (path-directory (this-source-file))) void))
          (def consumer (yuanxu-prepare-module-retained-source source void))
          (parameterize ((current-build-output-directory (path-expand "lib" directory)))
            (call-with-module-compiler-inputs (map entry (list language consumer))
              (lambda ()
                (def module
                  (import-module
                    (path-expand "language-fixture/value.ss" (current-build-source-directory)) #f #f))
                (check-equal? (expander-context-id module) 'language-fixture/value))
              unified?: #t))
          (write-source source "(export value) (def value #f)\n")
          (check-exception ((.ref consumer 'admit-current)) error?))))))
