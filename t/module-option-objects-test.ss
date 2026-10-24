;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-suite)
        (only-in :clan/poo/object .ref object?)
        :yuanxu/observability/testing-case
        :yuanxu/module-system/projection/option-objects
        :yuanxu/module-system/projection/option-validation)

(export module-option-objects-test)

(def module-option-objects-test
  (test-suite "Core Module option POO values"
    (yuanxu-test-case "configuration, schema, and receipt preserve native slots"
      (let* ((config
              (make-yuanxu-module-option-config
               "enabled" #t 'module-a '((owner . core))))
             (schema
              (make-yuanxu-module-option-schema
               "enabled" 'module-a 'Boolean 'constant #t '()))
             (receipt
              (make-yuanxu-module-option-validation-receipt
               "enabled" 'module-a #t 'ok '() '())))
        (check-equal? (object? config) #t)
        (check-equal? (yuanxu-module-option-config? config) #t)
        (check-equal? (yuanxu-module-option-config-value config) #t)
        (check-equal? (yuanxu-module-option-schema? schema) #t)
        (check-equal? (yuanxu-module-option-schema-rule schema) 'constant)
        (check-equal? (yuanxu-module-option-validation-receipt? receipt) #t)
        (check-equal? (.ref receipt 'valid?) #t)))
    (yuanxu-test-case "pure validation preserves order and typed outcomes"
      (let* ((schema
              (make-yuanxu-module-option-schema
               "enabled" 'module-a 'Boolean 'constant #t '()))
             (matched
              (make-yuanxu-module-option-config
               "enabled" #t 'module-a '()))
             (mismatched
              (make-yuanxu-module-option-config
               "enabled" #f 'module-a '()))
             (missing
              (make-yuanxu-module-option-config
               "absent" 1 'module-a '()))
             (receipts
              (yuanxu-module-options-validate
               (lambda (id) (yuanxu-module-find-schema (list schema) id))
               (list matched mismatched missing))))
        (check-equal? (length receipts) 3)
        (check-equal?
         (map yuanxu-module-option-validation-receipt-code receipts)
         '(ok constant-mismatch missing-schema))
        (check-equal?
         (map yuanxu-module-option-validation-receipt-valid? receipts)
         '(#t #f #f))))))
