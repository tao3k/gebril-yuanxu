;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander core-import-module expander-context-id core-bind-root-syntax!)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in "./qualification/testing/directory.ss" DirectoryFixture write-source)
        (only-in :yuanxu/utilities/functional yuanxu-stable-duplicates)
        (only-in :yuanxu/module-system/building/source-closure
                 for-each-build-module)
        (only-in :yuanxu/module-system/building/source-package module-build-source-path))
(export package-identity-test)

(def package-identity-test
  (test-suite "One Yuanxu package root"
    (test-case "ordinary explicit import does not require a package prelude"
      (check-equal? (yuanxu-stable-duplicates '(a b a c b))
                    '(a b)))
    (test-case "compiler identities map back to the same root source"
      (def context (core-import-module ':yuanxu/module-system/source/declaration))
      (def root (path-expand ".." (path-directory (this-source-file))))
      (check-equal? (expander-context-id context)
                    'yuanxu/module-system/source/declaration)
      (def before (load-path))
      (check-equal? (path-normalize (module-build-source-path context root))
                    (path-normalize (path-expand "module-system/source/declaration.ss" root)))
      (check-equal? (path-normalize (module-build-source-path
                      (core-import-module ':yuanxu/prelude) root))
                    (path-normalize (path-expand "prelude.ss" root)))
      (check-equal? (load-path) before))
    (test-case "runtime dependency closure includes the selected language entry"
      (def identities '())
      (for-each-build-module (core-import-module ':yuanxu/utilities/functional)
        (lambda (context) (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'yuanxu/prelude identities) #t) #t))
    (yuanxu-test-fixture "bound language uses its runtime source rather than a guessed package filename"
      (fixture DirectoryFixture)
      (def root (.get fixture root))
      (def source (path-expand "language.ss" root))
      (write-source (path-expand "gerbil.pkg" root) "(package: source-package)\n")
      (write-source source "prelude: :gerbil/core\npackage: language-origin\n(export)\n(error \"language initializer must remain lazy\")\n")
      (def language (core-import-module source))
      (core-bind-root-syntax! ':language-origin/language language #t)
      (check-equal? (path-normalize (module-build-source-path language root))
                    (path-normalize source))
      (def consumer (path-expand "consumer.ss" root))
      (write-source consumer "prelude: :language-origin/language\npackage: source-package\n")
      (def visited '())
      (for-each-build-module (core-import-module consumer)
        (lambda (context) (set! visited (cons context visited))))
      (check-equal? (and (memq language visited) #t) #t)
      (delete-file source)
      (check-equal?
        (with-catch (lambda (_missing-source) 'rejected)
          (lambda () (module-build-source-path language root) 'accepted))
        'rejected))))
