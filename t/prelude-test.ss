;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 resolve-identifier datum->syntax core-import-module expander-context-id
                 core-module->prelude-context module-context-export module-context-import
                 module-export-name module-export-phi import-set? import-set-source)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module))
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
    (test-case "the role prelude preserves native POO binding identity"
      (def language (core-import-module ':tao3k/yuanxu/module-system/source/module-prelude))
      (def poo (core-import-module ':clan/poo/object))
      (for-each
        (lambda (entry)
          (def name (module-export-name entry))
          (def phi (module-export-phi entry))
          (check-equal? (eq? (language-binding language name phi)
                            (language-binding poo name phi)) #t))
        (module-context-export poo))
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
                  (import :gerbil/core :clan/poo/object
                    (phi: +1 :gerbil/core) (phi: +2 :gerbil/core))
                  (export (except-out (import: :gerbil/core) object? make-object)
                    (import: :clan/poo/object)
                    (phi: +1 (import: :gerbil/core))
                    (phi: +2 (import: :gerbil/core)) (phi: 1 load-module))))))
          (def (trace context)
            (def result '())
            (for-each-build-module context
              (lambda (dependency)
                (unless (eq? dependency context)
                  (set! result (cons (expander-context-id dependency) result)))))
            (reverse result))
          (def former (core-import-module path))
          (def grouped (core-import-module ':tao3k/yuanxu/module-system/source/module-prelude))
          (def expected (trace former))
          (check-equal? expected (trace grouped))
          (displayln "ROLE-PRELUDE imports-before=" (length (module-context-import former))
                     " imports-after=" (length (module-context-import grouped))
                     " ordered-source-owners=" (length expected)))))
    (test-case "Prelude and explicit declaration import retain one terminal binding"
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (eval-syntax '(import (only-in :tao3k/yuanxu/prelude yuanxu! yuanxu-autoload define-yuanxu-module-declaration)))
        (def inherited-yuanxu (resolve-identifier (datum->syntax #f 'yuanxu!)))
        (def inherited-autoload (resolve-identifier (datum->syntax #f 'yuanxu-autoload)))
        (def inherited-decl (resolve-identifier (datum->syntax #f 'define-yuanxu-module-declaration)))
        (check-equal? (and inherited-yuanxu #t) #t)
        (eval-syntax '(import :tao3k/yuanxu/lang))
        (check-equal? (eq? inherited-yuanxu (resolve-identifier (datum->syntax #f 'yuanxu!))) #t)
        (check-equal? (eq? inherited-autoload (resolve-identifier (datum->syntax #f 'yuanxu-autoload))) #t)
        (check-equal? (eq? inherited-decl (resolve-identifier (datum->syntax #f 'define-yuanxu-module-declaration))) #t)
        (eval-syntax '(import (only-in :tao3k/yuanxu/module-system/selection/init-syntax yuanxu!)))
        (check-equal? (eq? inherited-yuanxu (resolve-identifier (datum->syntax #f 'yuanxu!))) #t)))
    (test-case "ordinary :tao3k/yuanxu/lang stays on :gerbil/core without POO or semantic bootstrap bloat"
      (def lang-identities '())
      (for-each-build-module (core-import-module ':tao3k/yuanxu/lang)
        (lambda (context) (set! lang-identities (cons (expander-context-id context) lang-identities))))
      (check-equal? (and (memq 'tao3k/yuanxu/module-system/selection/init-syntax lang-identities) #t) #t)
      (for-each (lambda (identity) (check-equal? (and (memq identity lang-identities) #t) #f))
        '(tao3k/yuanxu/prelude
          tao3k/yuanxu/module-system/selection/init-expansion
          tao3k/yuanxu/module-system/source/init
          tao3k/yuanxu/module-system/building/interface))
      ;; Importing :tao3k/yuanxu/lang must NOT shadow :gerbil/core's object?/make-object.
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
        (def core-object? (resolve-identifier (datum->syntax #f 'object?)))
        (def core-make-object (resolve-identifier (datum->syntax #f 'make-object)))
        (eval-syntax '(import :tao3k/yuanxu/lang))
        (check-equal? (eq? core-object? (resolve-identifier (datum->syntax #f 'object?))) #t)
        (check-equal? (eq? core-make-object (resolve-identifier (datum->syntax #f 'make-object))) #t)))
    (test-case "language bootstrap has no semantic declaration implementation dependency"
      (def identities '())
      (for-each-build-module (core-import-module ':tao3k/yuanxu/prelude)
        (lambda (context) (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'tao3k/yuanxu/module-system/selection/init-syntax identities) #t) #t)
      (for-each (lambda (identity) (check-equal? (and (memq identity identities) #t) #f))
        '(tao3k/yuanxu/module-system/selection/init-expansion tao3k/yuanxu/module-system/source/init
          tao3k/yuanxu/module-system/building/interface)))
    (test-case "ordinary values and prototype refinement"
      (.def Baseline commands: '("gerbil" "build") port: 5432)
      (.def (Release @ Baseline) port: 5440)
      (check-equal? (.get Release port) (expected-port-literal))
      (check-equal? (.get Release commands) '("gerbil" "build"))
      (check-equal? (.get Baseline port) 5432))))
