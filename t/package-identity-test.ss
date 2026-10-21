;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :yuanxu/utilities/functional yuanxu-map)
        (only-in :yuanxu/module-system/building/source-closure
                 yuanxu-bootstrap-source-path for-each-build-module))
(export package-identity-test)

(def package-identity-test
  (test-suite "One Yuanxu package root"
    (test-case "ordinary explicit import does not require a package prelude"
      (check-equal? (yuanxu-map number->string '(5432 5440))
                    '("5432" "5440")))
    (test-case "compiler identities map back to the same root source"
      (def context (core-import-module ':yuanxu/module-system/source/declaration))
      (def root (path-expand ".." (path-directory (this-source-file))))
      (check-equal? (expander-context-id context)
                    'yuanxu/module-system/source/declaration)
      (check-equal? (yuanxu-bootstrap-source-path context root)
                    (path-expand "module-system/source/declaration.ss" root))
      (check-equal? (yuanxu-bootstrap-source-path
                      (core-import-module ':tao3k/yuanxu/prelude) root)
                    (path-expand "prelude.ss" root)))
    (test-case "native dependency closure includes the selected language entry"
      (def identities '())
      (for-each-build-module (core-import-module ':yuanxu/utilities/functional)
        (lambda (context) (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'tao3k/yuanxu/prelude identities) #t) #t))))
