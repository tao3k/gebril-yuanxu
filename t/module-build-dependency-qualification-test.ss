;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Gerbil prepares the dependency package once; tests consume its public units.
(import :std/test
        (only-in :clan/poo/object .get .call)
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander core-import-module expander-context-id core-read-module/sexp)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture))
(export module-build-dependency-qualification-test test-setup! test-cleanup!)
(def Fixture (selection-fixture (path-expand ".." (path-directory (this-source-file)))))
(def resource #f)
(def (test-setup!) (set! resource (.call Fixture .acquire)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource) (set! resource #f))))
(def module-build-dependency-qualification-test
  (test-suite "Prepared public dependencies remain separate from Core"
    (test-case "the actual compiler closure resolves to prepared POO units"
      (def context (core-import-module ':tao3k/yuanxu/module-system/building/build-projection))
      (def state (.get resource state))
      (def seen (make-hash-table-eq))
      (for-each-build-module context
        (lambda (child)
          (def id (expander-context-id child))
          (when (and (symbol? id) (string-prefix? "clan/poo/" (symbol->string id)))
            (hash-put! seen id #t))))
      (check-equal? (> (hash-length seen) 0) #t)
      (hash-for-each
        (lambda (id _)
          (def path (path-expand (string-append "lib/" (symbol->string id) ".ssi") state))
          (check-equal? (file-exists? path) #t)
          (let-values (((_prelude actual _namespace _body) (core-read-module/sexp path)))
            (check-equal? actual id))) seen)
      ;; This is readiness, not another partial gerbil-poo build or ABI proof.
      (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" state)) #f)
      (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" state)) #f))))
