;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context)
        (only-in :clan/poo/object .get .ref .o)
        (only-in :yuanxu/module-system/source/role-forms
                 module-publication-role-imports module-regular-role-file?)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-source-ref)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-publication))
(export module-role-projection-test)
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (with-module test)
  (call-with-temporary-directory "role-projection"
    (lambda (root)
      (def prefix (symbol->string (gensym 'role-projection-)))
      (write-source (path-expand "gerbil.pkg" root)
        (string-append "(package: " prefix
          " prelude: :yuanxu/module-system/source/module-prelude)\n"))
      (write-source (path-expand "types.ss" root)
        "(import (only-in :yuanxu/types yuanxu-predicate-contract)) (def ScopeContract (yuanxu-predicate-contract 'role/scope object? (lambda (_v _c) '()))) (export ScopeContract)\n")
      (write-source (path-expand "objects.ss" root)
        "(.def Value answer: 42) (export Value)\n")
      (write-source (path-expand "func.ss" root)
        "(def (value-of x) (.ref x 'answer)) (export value-of)\n")
      (write-source (path-expand "config.ss" root)
        "(.def Config mode: 'check) (export Config)\n")
      (write-source (path-expand "interface.ss" root)
        "(.def Published identity: 'fixture core: (.o requires: (.o) scope-contract: ScopeContract exports: (.o answer: (value-of Value) config: Config)) features: (.o))\n")
      (test root prefix))))
(def module-role-projection-test
  (test-suite "One role inventory for declaration and compiler"
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
          (parameterize ((current-expander-context (make-top-context)))
            (eval-syntax '(import :gerbil/core))
            (eval-syntax `(import ,(path-expand "interface.ss" root)))
            (def published (eval-syntax 'Published))
            (def effective ((.get published core link) (.o)))
            (check-equal? (.get published identity) 'fixture)
            (check-equal? (.get effective answer) 42)
            (check-equal? (.get effective config mode) 'check)
            (check-equal? (with-catch (lambda (_e) #t)
                            (lambda () (eval-syntax 'Config) #f)) #t)))))
    (test-case "role scanning rejects symlinks and distinguishes missing optional roles"
      (with-module
        (lambda (root _prefix)
          (delete-file (path-expand "func.ss" root))
          (check-equal? (module-publication-role-imports root module-regular-role-file?)
                        '("./types.ss" "./objects.ss" "./config.ss"))
          (create-symbolic-link (path-expand "objects.ss" root) (path-expand "func.ss" root))
          (check-exception (module-publication-role-imports root module-regular-role-file?) error?))))))
