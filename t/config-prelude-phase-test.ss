;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/make make)
        (only-in :gerbil/runtime/loader load-path set-load-path!)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context))
(export config-prelude-phase-test)
(def config-prelude-phase-test
  (test-suite "Native role prelude compiler phases"
    (test-case "An installed SSI can load its syntax-phase object"
      (call-with-temporary-directory "role-prelude-phase"
        (lambda (root)
          (def name (symbol->string (gensym 'native-role-phase-)))
          (def source (path-expand (string-append name ".ss") root))
          (call-with-output-file source
            (lambda (out)
              (display "prelude: :yuanxu/module-system/source/config-prelude\n" out)
              (display "(defsyntax answer (identifier-rules () (_ 42)))\n(export answer)\n" out)))
          (def lib (path-expand "lib" root))
          (make (list name) srcdir: root libdir: lib optimize: #f)
          ;; A fresh expander must read the generated SSI, not the source context.
          (def previous (load-path))
          (dynamic-wind
            (lambda () (set-load-path! (cons lib previous)))
            (lambda ()
              (parameterize ((current-expander-context (make-top-context)))
                (eval-syntax `(import ,(path-expand (string-append name ".ssi") lib)))
                (check-equal? (eval-syntax 'answer) 42)))
            (lambda () (set-load-path! previous))))))))
