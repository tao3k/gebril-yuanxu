;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 call-with-module-source-read-cache)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/module-system/source/preparation
                 yuanxu-prepare-module-retained-source))
(export module-retained-source-test)
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def module-retained-source-test
  (test-suite "Ordinary retained libraries keep native export semantics"
    (yuanxu-test-case "different ancestor lists share package identity only within one pure window"
      (call-with-temporary-directory "retained-package"
        (lambda (root)
          (def package (path-expand "gerbil.pkg" root))
          (def nested (path-expand "child" root))
          (create-directory nested)
          (write-source package
            (string-append "(package: " (symbol->string (gensym 'retained-)) ")"))
          (def first (path-expand "first.ss" root))
          (def second (path-expand "second.ss" nested))
          (write-source first "(def Value 1) (export Value)\n")
          (write-source second "(def Value 2) (export Value)\n")
          (def left (yuanxu-prepare-module-retained-source first void))
          (def right (yuanxu-prepare-module-retained-source second void))
          (def requests 0)
          (parameterize ((current-module-source-observer
                          (lambda (key amount)
                            (when (and (pair? key) (eq? (car key) 'file-request)
                                       (equal? (caddr key) package))
                              (set! requests (+ requests amount))))))
            (call-with-module-source-read-cache
              (lambda ()
                ((.get left admit-current))
                ((.get right admit-current))))
            (check-equal? requests 1)
            ((.get right admit-current))
            (check-equal? requests 2))
          ;; A closer package appeared after the window. Its earlier negative
          ;; observation must still reject, before trusting a cached SDK lookup.
          (write-source (path-expand "gerbil.pkg" nested) "(package: replacement)")
          (check-exception ((.get right admit-current)) error?)
          (write-source package "(package: changed)")
          (check-exception ((.get left admit-current)) error?))))
    (test-case "config filename does not opt a retained library into a Module role"
      (call-with-temporary-directory "retained-config"
        (lambda (root)
          (def source (path-expand "config.ss" root))
          (def wrapper (path-expand "wrapped.ss" root))
          (write-source (path-expand "gerbil.pkg" root)
            (string-append "(package: " (symbol->string (gensym 'retained-)) ")"))
          (write-source source "(def Config 23) (def PublicValue 42) (export PublicValue)\n")
          (def prepared (yuanxu-prepare-module-retained-source source void))
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
