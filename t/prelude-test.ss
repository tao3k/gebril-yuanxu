;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 resolve-identifier datum->syntax core-import-module expander-context-id
                 core-module->prelude-context module-context-export module-context-import
                 module-export-name module-export-phi import-set? import-set-source)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module))
(export prelude-test)

;; The public root prelude supplies POO bindings without an explicit POO import.
(begin-syntax
  (begin-syntax (def fixture-port 5440))
  (defsyntax (port-literal stx) (datum->syntax (stx-car stx) fixture-port))
  (def expected-port (port-literal)))
(defsyntax (expected-port-literal stx) (datum->syntax (stx-car stx) expected-port))

;; Resolve through the real weak prelude frame. No copied name/type inventory
;; or manufactured binding identity substitutes for Gerbil's terminal binding.
(def (language-binding context name phi)
  (parameterize ((current-expander-context
                  (make-top-context (core-module->prelude-context context))))
    (resolve-identifier (datum->syntax #f name) phi)))

(def prelude-test
  (test-suite "Yuanxu package prelude"
    (test-case "grouped role imports preserve public binding identity and dedicated declaration"
      (def language (core-import-module ':yuanxu/module-system/source/module-prelude))
      (def poo (core-import-module ':clan/poo/object))
      (def declaration (core-import-module ':yuanxu/module-system/source/declaration))
      (for-each
        (lambda (entry)
          (def name (module-export-name entry))
          (def phi (module-export-phi entry))
          (unless (eq? name '.def)
            (check-equal? (eq? (language-binding language name phi)
                              (language-binding poo name phi)) #t)))
        (module-context-export poo))
      (check-equal? (eq? (language-binding language '.def 0)
                        (language-binding declaration '.def 0)) #t)
      (check-equal? (language-binding language 'role-.def 0) #f)
      ;; Whole-owner import replaces per-name aliases in the local prelude.
      ;; The callback/source owner remains the same actual runtime context.
      (check-equal?
        (length (filter (lambda (entry)
                          (and (import-set? entry) (eq? (import-set-source entry) poo)))
                        (module-context-import language))) 1)
      ;; A normal explicit strong import must still override the weak language.
      (parameterize ((current-expander-context
                      (make-top-context (core-module->prelude-context language))))
        (eval-syntax '(import (only-in :clan/poo/object .def)))
        (check-equal? (eq? (resolve-identifier (datum->syntax #f '.def))
                          (language-binding poo '.def 0)) #t)))
    (test-case "grouped role imports preserve the ordered dependency callback trace"
      (call-with-temporary-directory "role-language-control-"
        (lambda (root)
          ;; Executable control for the former language import form. Expected
          ;; dependency order comes from Gerbil, not a handwritten owner list.
          (def path (path-expand "control.ss" root))
          (call-with-output-file path
            (lambda (port)
              (for-each (lambda (form) (write form port) (newline port))
                '(prelude: :gerbil/core
                  (import :gerbil/core (except-in :clan/poo/object .def)
                    (only-in :yuanxu/module-system/source/declaration .def)
                    (phi: +1 :gerbil/core) (phi: +2 :gerbil/core))
                  (export (except-out (import: :gerbil/core) object? make-object)
                    (import: :clan/poo/object)
                    (phi: +1 (import: :gerbil/core))
                    (phi: +2 (import: :gerbil/core)) (phi: 1 load-module) .def)))))
          (def (trace context)
            (def result '())
            (for-each-build-module context
              (lambda (dependency)
                (unless (eq? dependency context)
                  (set! result (cons (expander-context-id dependency) result)))))
            (reverse result))
          (def former (core-import-module path))
          (def grouped (core-import-module ':yuanxu/module-system/source/module-prelude))
          (def expected (trace former))
          (check-equal? expected (trace grouped))
          (check-equal? (> (length (module-context-import former))
                           (length (module-context-import grouped))) #t)
          (displayln "ROLE-PRELUDE imports-before=" (length (module-context-import former))
                     " imports-after=" (length (module-context-import grouped))
                     " ordered-source-owners=" (length expected)))))
    (test-case "Prelude and explicit declaration import retain one terminal binding"
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax '(import (only-in :yuanxu/prelude yuanxu!)))
        (def inherited (resolve-identifier (datum->syntax #f 'yuanxu!)))
        (check-equal? (and inherited #t) #t)
        (eval-syntax '(import (only-in :yuanxu/module-system/selection/init-syntax yuanxu!)))
        (check-equal? (eq? inherited (resolve-identifier (datum->syntax #f 'yuanxu!))) #t)))
    (test-case "language bootstrap has no semantic declaration implementation dependency"
      (def identities '())
      (for-each-build-module (core-import-module ':yuanxu/prelude)
        (lambda (context) (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'yuanxu/module-system/selection/init-syntax identities) #t) #t)
      (for-each (lambda (identity) (check-equal? (and (memq identity identities) #t) #f))
        '(yuanxu/module-system/selection/init-expansion yuanxu/module-system/source/init
          yuanxu/module-system/building/interface)))
    (test-case "ordinary values and prototype refinement"
      (.def Baseline commands: '("gerbil" "build") port: 5432)
      (.def (Release @ Baseline) port: 5440)
      (check-equal? (.get Release port) (expected-port-literal))
      (check-equal? (.get Release commands) '("gerbil" "build"))
      (check-equal? (.get Baseline port) 5432))))
