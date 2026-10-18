;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context)
        (only-in :clan/poo/object .get)
        (only-in :core/module-system/source/preparation
                 poo-flow-prepare-module-retained-source))
(export module-retained-source-test)
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def module-retained-source-test
  (test-suite "Ordinary retained libraries keep native export semantics"
    (test-case "config filename does not opt a retained library into a Module role"
      (call-with-temporary-directory "retained-config"
        (lambda (root)
          (def source (path-expand "config.ss" root))
          (def wrapper (path-expand "wrapped.ss" root))
          (write-source (path-expand "gerbil.pkg" root)
            (string-append "(package: " (symbol->string (gensym 'retained-)) ")"))
          (write-source source "(def Config 23) (def PublicValue 42) (export PublicValue)\n")
          (def prepared (poo-flow-prepare-module-retained-source source void))
          (call-with-output-file wrapper
            (lambda (port)
              (for-each (lambda (form) (write form port) (newline port))
                        (.get prepared compiler-forms))))
          (parameterize ((current-expander-context (make-top-context)))
            (eval-syntax `(import ,wrapper))
            (check-equal? (eval-syntax 'PublicValue) 42)
            (check-equal?
              (with-catch
                (lambda (exception)
                  (if (pregexp-match "Reference to unbound identifier"
                        (call-with-output-string
                          (lambda (port) (display-exception exception port)))) #t #f))
                (lambda () (eval-syntax 'Config) #f)) #t)))))))
