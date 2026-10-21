;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure option validation over Core Module POO values. Descriptor-specific
;;; schema discovery remains with the product adapter.

(import (only-in :yuanxu/module-system/config yuanxu-module-kind=?)
        :yuanxu/module-system/projection/option-objects)

(export yuanxu-module-find-schema
        yuanxu-module-missing-schema-receipt
        yuanxu-module-option-schema-validation-receipt
        yuanxu-module-options-validate)

(def (yuanxu-module-find-schema schemas option-id-value)
  (find (lambda (schema)
          (yuanxu-module-kind=? (yuanxu-module-option-schema-id schema)
                                  option-id-value))
        schemas))

(def (yuanxu-module-missing-schema-receipt config)
  (make-yuanxu-module-option-validation-receipt
   (yuanxu-module-option-config-id config)
   (yuanxu-module-option-config-source-module config)
   #f
   'missing-schema
   '("option schema is not declared")
   '()))

(def (yuanxu-module-option-schema-valid? schema config)
  (if (eq? (yuanxu-module-option-schema-rule schema) 'constant)
    (equal? (yuanxu-module-option-config-value config)
            (yuanxu-module-option-schema-value schema))
    #t))

(def (yuanxu-module-option-schema-validation-receipt schema config)
  (if (yuanxu-module-option-schema-valid? schema config)
    (make-yuanxu-module-option-validation-receipt
     (yuanxu-module-option-config-id config)
     (yuanxu-module-option-config-source-module config)
     #t
     'ok
     '()
     (yuanxu-module-option-schema-metadata schema))
    (make-yuanxu-module-option-validation-receipt
     (yuanxu-module-option-config-id config)
     (yuanxu-module-option-config-source-module config)
     #f
     'constant-mismatch
     '("option value does not match constant schema")
     (yuanxu-module-option-schema-metadata schema))))

;; Preserve input order while traversing only once; schema-ref is supplied by
;; the owner of the concrete Module Interface or descriptor.
(def (yuanxu-module-options-validate schema-ref configs)
  (let loop ((remaining configs) (receipts-rev '()))
    (if (null? remaining)
      (reverse receipts-rev)
      (let* ((config (car remaining))
             (schema (schema-ref (yuanxu-module-option-config-id config))))
        (loop (cdr remaining)
              (cons (if schema
                      (yuanxu-module-option-schema-validation-receipt
                       schema config)
                      (yuanxu-module-missing-schema-receipt config))
                    receipts-rev))))))
