;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/mop TypeError?)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get .ref .call .cc .o .+)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/modules/json-schema/json-schema-validate
                 yuanxu-json-schema-object-contract-validation?
                 yuanxu-json-schema-object-contract-validation-valid?
                 yuanxu-json-schema-object-contract-validation-diagnostics
                 yuanxu-json-schema-validation-diagnostic?)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-json-schema-publication-test)
(def root (path-expand ".." (path-directory (this-source-file))))
;; Private-source drift/cycles require the complete source-only package, not a
;; partial copy sharing canonical Core IDs. See module-source-spec-test and
;; module-reader-tool-context-test for those controls.
(def module-json-schema-publication-test
  (test-suite "Real JsonSchema publication and native private-source closure"
    (yuanxu-test-case "real Core init publishes contracts and derives all imported sources once"
      (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
             (graph (.get view build-graph))
             (scope (.get view modules Modules json-schema))
             (contract (.call scope contract 'test/port
                        '((type . "object") (required . ("port"))
                          (properties . ((port . ((type . "integer") (minimum . 1)))))))))
        (check-equal? (.get view selected-graph module-order)
                      '(json-schema funflow services/postgresql services/gitea applications/gitea-postgresql))
        (check-equal? (> (length (.get graph entries)) 15) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o port: 80) #f)) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit contract (.o port: "bad") #f)) #f)
        (check-exception (.call scope compile 4) TypeError?)
        (def artifact (.call scope compile
                        '((type . "object")
                          (properties . ((port . ((type . "integer"))))))))
        (def validation (.call scope validate artifact (.o port: "bad")))
        (check-equal? (yuanxu-json-schema-object-contract-validation? validation) #t)
        (check-equal? (yuanxu-json-schema-object-contract-validation-valid? validation) #f)
        (check-equal?
          (yuanxu-json-schema-validation-diagnostic?
            (car (yuanxu-json-schema-object-contract-validation-diagnostics validation))) #t)
        ;; A callable recognizer alone would let this result escape. Admission
        ;; must install the native result wrapper in the actual returned Scope.
        (def checked (.get (yuanxu-contract-admit (.get scope types scope)
                            (.cc scope 'compile (lambda () 7)) #f) candidate))
        (check-exception (.call checked compile) TypeError?)
        (check-exception
          (yuanxu-contract-admit (.get scope types scope)
            (.+ scope (.o defaults: (.o scheam: '()))) #f) TypeError?)
        (check-exception
          (yuanxu-contract-admit (.get scope types scope)
            (.+ scope (.o compile: 7)) #f) TypeError?)
        (check-equal? (.get scope defaults schema) '((type . "object")))))
))
