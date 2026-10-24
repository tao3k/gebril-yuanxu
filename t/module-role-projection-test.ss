;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/make make)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context)
        (only-in :clan/poo/object .get .ref .o)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in :yuanxu/module-system/source/role-forms
                 module-publication-role-imports module-regular-role-file?)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-source-ref)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-publication
                 yuanxu-prepare-module-build-source call-with-module-compiler-inputs))
(export module-role-projection-test)
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (with-module test)
  (call-with-temporary-directory "role-projection"
    (lambda (root)
      (def prefix (symbol->string (gensym 'role-projection-)))
      (write-source (path-expand "gerbil.pkg" root)
        (string-append "(package: " prefix
          " prelude: :gerbil/core)\n"))
      (write-source (path-expand "types.ss" root)
        "(import (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)) (def ScopeContract (yuanxu-predicate-contract 'role/scope object? (lambda (_v _c) '()))) (export ScopeContract)\n")
      (write-source (path-expand "objects.ss" root)
        "(import (only-in :std/source this-source-file)) (.def Value answer: 42 origin: (this-source-file)) (export Value)\n")
      (write-source (path-expand "func.ss" root)
        "(def (value-of x) (.ref x 'answer)) (export value-of)\n")
      (write-source (path-expand "config.ss" root)
        "(.def Config mode: 'check) (export Config)\n")
      (write-source (path-expand "interface.ss" root)
        "(.def Published identity: 'fixture core: (.o requires: (.o) scope-contract: ScopeContract exports: (.o answer: (value-of Value) origin: (.get Value origin) config: Config)) features: (.o))\n")
      (test root prefix))))
(def module-role-projection-test
  (test-suite "One role inventory for declaration and compiler"
    (test-case "SDK spec syntax evaluates its value and options once"
      (let ()
        (def specifications 0)
        (def options 0)
        (defbuild-script
          (begin (set! specifications (1+ specifications)) '("library"))
          libdir: (begin (set! options (1+ options)) (gerbil-path)))
        (def printed
          (call-with-output-string
            (lambda (out)
              (parameterize ((current-output-port out)) (main "spec")))))
        (check-equal? (call-with-input-string printed read) '("library"))
        (check-equal? specifications 1)
        (check-equal? options 1)))
    (test-case "publication frames and standard source expansion agree"
      (with-module
        (lambda (root _prefix)
          (def imports (module-publication-role-imports root module-regular-role-file?))
          (check-equal? imports '("./types.ss" "./objects.ss" "./func.ss" "./config.ss"))
          (def source (make-yuanxu-module-source-ref 'local (path-expand "interface.ss" root)
                         (list (cons 'module-id 'fixture) (cons 'module-root root))))
          (def prepared (yuanxu-prepare-module-publication source))
          (check-equal? (map path-strip-directory (.get prepared role-sources))
                        (map path-strip-directory imports))
          (def entries
            (cons (.o path: (path-expand "interface.ss" root) input: prepared)
              (map (lambda (file)
                     (.o path: file input: (yuanxu-prepare-module-build-source file void)))
                (.get prepared role-sources))))
          (call-with-module-compiler-inputs entries
           (lambda ()
            (parameterize ((current-expander-context (make-top-context)))
            (eval-syntax '(import :gerbil/core))
            (eval-syntax `(import ,(path-expand "interface.ss" root)))
            (def published (eval-syntax 'Published))
            (def effective ((.get published core link) (.o)))
            (check-equal? (.get published identity) 'fixture)
            (check-equal? (.get effective answer) 42)
            (check-equal? (path-normalize (.get effective origin))
                          (path-normalize (path-expand "objects.ss" root)))
            (check-equal? (.get effective config mode) 'check)
            (check-equal? (with-catch (lambda (_e) #t)
                            (lambda () (eval-syntax 'Config) #f)) #t)))))))
    (test-case "native Make consumes the same role frames without nested package metadata"
      (with-module
        (lambda (root prefix)
          (def source (make-yuanxu-module-source-ref 'local (path-expand "interface.ss" root)
                         (list (cons 'module-id 'fixture) (cons 'module-root root))))
          (def publication (yuanxu-prepare-module-publication source))
          (def entries
            (cons (.o path: (path-expand "interface.ss" root) input: publication)
              (map (lambda (file)
                     (.o path: file input: (yuanxu-prepare-module-build-source file void)))
                (.get publication role-sources))))
          (def lib (path-expand "lib" root))
          (def spec (map (lambda (entry) (path-strip-extension (path-strip-directory (.get entry path)))) entries))
          (def (compile!)
            (call-with-module-compiler-inputs entries
              (lambda () (make spec srcdir: root libdir: lib prefix: prefix parallelize: 1))))
          (compile!)
          (def output (path-expand (string-append prefix "/interface.ssi") lib))
          (def before (time->seconds (file-info-last-modification-time (file-info output))))
          (compile!)
          (check-equal? (time->seconds (file-info-last-modification-time (file-info output))) before)
          (check-equal? (file-exists? (path-expand (string-append prefix "/interface.o2") lib)) #f)
          (write-source (path-expand "objects.ss" root) "(.def Value answer: 99) (export Value)\n")
          (check-exception (compile!) error?))))
    (test-case "role scanning rejects symlinks and distinguishes missing optional roles"
      (with-module
        (lambda (root _prefix)
          (delete-file (path-expand "func.ss" root))
          (check-equal? (module-publication-role-imports root module-regular-role-file?)
                        '("./types.ss" "./objects.ss" "./config.ss"))
          (create-symbolic-link (path-expand "objects.ss" root) (path-expand "func.ss" root))
          (check-exception (module-publication-role-imports root module-regular-role-file?) error?))))))
