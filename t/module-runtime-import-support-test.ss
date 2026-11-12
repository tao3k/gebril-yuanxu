;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-import-module module-context-path current-expander-eval)
        (only-in :tao3k/yuanxu/ops/objects ProcessScript.)
        (only-in :tao3k/yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in "qualification/module-publication/fixtures.ss"
                 PublicLibraryFixture with-publication-source write-file gerbil-import-value))
(export module-runtime-import-support-test)

(def (with-compiled-library procedure (greeting '(.get State value)))
  (with-yuanxu-fixture (library PublicLibraryFixture)
    (def source (.get library path))
    (def source-directory (path-directory source))
    (def output (path-expand ".." source-directory))
    (def identity (string->symbol
                    (string-append ":" (path-strip-directory
                      (path-strip-trailing-directory-separator source-directory)) "/helper")))
    (write-file source
      "(import :clan/poo/object) (export State Snapshot)\n\
       (def State (.o value: 0))\n\
       (.get State value)\n\
       (.put! State 'value 1)\n\
       (def Snapshot (.get State value))\n")
    (.def (Compiler @ ProcessScript.)
      command: (list "gerbil" "-:max-heap=2G,debug=q" "env" "gxc" "-d" output)
      directory: source-directory timeout: 60 check-status: #f)
    (def compiled (.call Compiler .run "helper.ss"))
    (unless (zero? (.get compiled status))
      (error "runtime library fixture compilation failed" (.get compiled status) (.get compiled output)))
    (with-publication-source
      (lambda (_root _module-root _source view) (procedure identity view))
      roles: (.o config:
                `((import (only-in ,identity State Snapshot))
                  (def Greeting ,greeting)
                  (export Greeting))))))

(def module-runtime-import-support-test
  (test-suite "Compiled dependency initialization and Scope support"
    (yuanxu-test-case "cold compiled construction is separate from the Scope's actual value read"
      (with-compiled-library
        (lambda (identity view)
          (check-equal? (.get view modules custom example greeting) 1)
          (def context (core-import-module identity))
          (check-equal? (path-extension (module-context-path context)) ".ssi")
          (def state (gerbil-import-value identity 'State))
          (.put! state 'value 2)
          (check-exception (.get view modules custom example greeting) error?))))
    (yuanxu-test-case "an initialization snapshot has the same support on cold and warm consumption"
      (with-compiled-library
        (lambda (identity view)
          (check-equal? (.get view modules custom example greeting) 1)
          (def state (gerbil-import-value identity 'State))
          (.put! state 'value 2)
          ;; This consumer reads the exported snapshot, not the live State.
          (check-equal? (.get view modules custom example greeting) 1))
        'Snapshot))
    (yuanxu-test-case "an admitted runtime Context cannot be retargeted after Scope publication"
      (with-compiled-library
        (lambda (identity view)
          (check-equal? (.get view modules custom example greeting) 1)
          (def context (core-import-module identity))
          (def origin (module-context-path context))
          (dynamic-wind
            (lambda () (slot-set! context 'path (string-append origin ".forged")))
            (lambda () (check-exception (.get view modules custom example greeting) error?))
            (lambda () (slot-set! context 'path origin))))))
    (yuanxu-test-case "an open evaluator runs and retains the Scope's actual value support"
      (def original (current-expander-eval))
      (def calls 0)
      (parameterize ((current-expander-eval
                      (lambda (program) (set! calls (1+ calls)) (original program))))
        (with-compiled-library
          (lambda (identity view)
            (check-equal? (.get view modules custom example greeting) 1)
            (check-equal? (> calls 0) #t)
            (def state (gerbil-import-value identity 'State))
            (.put! state 'value 2)
            (check-exception (.get view modules custom example greeting) error?)))))
    (yuanxu-test-case "an open evaluator still accepts an initialized dependency and checks its live value"
      (def original (current-expander-eval))
      (with-compiled-library
        (lambda (identity view)
          ;; An explicit prerequisite control, never a warmed business Scope.
          (def state (gerbil-import-value identity 'State))
          (parameterize ((current-expander-eval (lambda (program) (original program))))
            (check-equal? (.get view modules custom example greeting) 1)
            (.put! state 'value 2)
            (check-exception (.get view modules custom example greeting) error?)))))))
