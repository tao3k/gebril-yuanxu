;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref object?)
        (only-in :std/test check-equal? test-suite)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/schema/interface
        :yuanxu/module-system/schema/validation)

(export module-schema-validation-test)

(def (schema-field identity type merge default metadata)
  (yuanxu-module-field-contract identity type merge default metadata))

(def module-schema-validation-test
  (test-suite "native POO module schema validation"
    (yuanxu-test-case "uses native Type and C4 without an ASP harness"
      (let* ((parent
              (yuanxu-module-object
               'schema.parent '()
               (list (schema-field 'name YuanxuModuleStringType
                                   'override "parent" '()))
               '()))
             (child
              (yuanxu-module-object
               'schema.child (list parent)
               (list (schema-field 'enabled YuanxuModuleBooleanType
                                   'override #t '()))
               '()))
             (validation (yuanxu-module-object-validation child))
             (summary
              (yuanxu-module-objects-validation-summary
               (yuanxu-module-objects-validation (list parent child)))))
        (check-equal? (yuanxu-module-object-validation? validation) #t)
        (check-equal? (eq? validation
                          (yuanxu-module-object-validation child))
                      #t)
        (check-equal? (yuanxu-module-object-validation-valid? validation)
                      #t)
        (check-equal? (.ref validation 'inheritance-chain)
                      '(schema.child schema.parent))
        (check-equal? (.ref validation 'resolved-field-identities)
                      '(name enabled))
        (check-equal? (map (lambda (origin) (.ref origin 'provider))
                           (.ref validation 'field-origins))
                      '(schema.parent schema.child))
        (check-equal? (.ref summary 'object-count) 2)
        (check-equal? (.ref summary 'invalid-count) 0)))

    (yuanxu-test-case "rejects invalid merge, metadata, and native default"
      (let* ((bad
              (yuanxu-module-object
               'schema.invalid '()
               (list (schema-field 'name YuanxuModuleStringType
                                   'unknown 42 'bad-metadata))
               '()))
             (validation (yuanxu-module-object-validation bad))
             (field-validation
              (car (.ref validation 'fieldContractValidations))))
        (check-equal? (yuanxu-module-object-validation-valid? validation)
                      #f)
        (check-equal? (object? field-validation) #t)
        (check-equal? (map (lambda (diagnostic) (.ref diagnostic 'code))
                           (.ref field-validation 'diagnostics))
                      '(unsupported-merge metadata-not-association-list
                        default-not-in-native-type))))

    (yuanxu-test-case "rejects merge operations incompatible with native types"
      (let* ((bad
              (yuanxu-module-object
               'schema.bad-merge '()
               (list (schema-field 'node YuanxuModuleStringType
                                   'node-extend #f '())
                     (schema-field 'target YuanxuModuleStringType
                                   'node-remove #f '()))
               '()))
             (validation (yuanxu-module-object-validation bad)))
        (check-equal? (yuanxu-module-object-validation-valid? validation) #f)
        (check-equal? (map (lambda (diagnostic) (.ref diagnostic 'code))
                           (.ref validation 'diagnostics))
                      '(merge-type-incompatible merge-type-incompatible))))

    (yuanxu-test-case "returns diagnostics for malformed field entries"
      (let* ((bad (yuanxu-module-object
                   'schema.bad-field '() '(not-a-contract) '()))
             (validation (yuanxu-module-object-validation bad)))
        (check-equal? (yuanxu-module-object-validation-valid? validation) #f)
        (check-equal? (map (lambda (diagnostic) (.ref diagnostic 'code))
                           (.ref validation 'diagnostics))
                      '(invalid-field-contract))))

    (yuanxu-test-case "rejects duplicate catalog identities"
      (let* ((first (yuanxu-module-object 'schema.duplicate '() '() '()))
             (second (yuanxu-module-object 'schema.duplicate '() '() '()))
             (summary (yuanxu-module-objects-validation-summary
                       (yuanxu-module-objects-validation
                        (list first second)))))
        (check-equal? (.ref summary 'valid) #f)
        (check-equal? (.ref summary 'duplicate-identities)
                      '(schema.duplicate))
        (check-equal?
         (with-catch
          (lambda (_) #t)
          (lambda ()
            (yuanxu-require-module-objects-validation!
             (list first second))
            #f))
         #t)))))
