;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-only Graph admission is independent of compiler execution.
(import (only-in :std/test test-suite check-equal?)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get .call .o)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules))
(export module-bootstrap-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def module-bootstrap-test
  (test-suite "Source tool consumes uncompiled JsonSchema publication"
    (yuanxu-test-case "shared-root DFS preserves identity without retaining a cross-call cache"
      (def roots
        (map core-import-module
          '(:yuanxu/module-system/building/build-projection
            :yuanxu/module-system/building/configuration-source)))
      (def expected (make-hash-table))
      (def repeated 0)
      (for-each (lambda (root)
                  (for-each-build-module root
                    (lambda (context)
                      (set! repeated (+ repeated 1))
                      (hash-put! expected (expander-context-id context) context)))) roots)
      (def (walk)
        (def seen (make-hash-table-eq))
        (def visits 0)
        (for-each (lambda (root)
                    (for-each-build-module root
                      (lambda (context)
                        (set! visits (+ visits 1))
                        (check-equal?
                          (eq? context (hash-ref expected (expander-context-id context))) #t))
                      seen)) roots)
        (check-equal? visits (hash-length expected))
        (check-equal? (< visits repeated) #t)
        visits)
      (def visits (walk))
      (check-equal? visits (walk))
      (yuanxu-test-observe 'bootstrap-root-visits repeated)
      (yuanxu-test-observe 'bootstrap-union-visits visits))
    (yuanxu-test-case "init selects a source Graph and exposes the declared Contract"
      (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
             (graph (.get view build-graph))
             (scope (.get view modules Modules json-schema))
             (contract (.call scope contract 'bootstrap/value
                         '((type . "object") (required . ("value"))
                           (properties . ((value . ((type . "string")))))))))
        (check-equal? (.get view selected-graph module-order)
                      '(json-schema funflow services/postgresql services/gitea applications/gitea-postgresql))
        (check-equal? (> (length (.get graph entries)) 15) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o value: "pass") #f)) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o value: 7) #f)) #f)))))
