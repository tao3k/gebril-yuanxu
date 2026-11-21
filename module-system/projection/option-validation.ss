;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure option validation over Core Module POO values. Descriptor-specific
;;; schema discovery remains with the product adapter.

(import (only-in :tao3k/yuanxu/module-system/config yuanxu-module-kind=? yuanxu-module-object-ref/default)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/value-diagnostics diagnose-value)
        (only-in :clan/poo/object-contract checked-issues)
        :tao3k/yuanxu/module-system/projection/option-objects)

(export yuanxu-module-find-schema
        yuanxu-module-missing-schema-receipt
        yuanxu-module-option-schema-validation-receipt
        yuanxu-module-options-validate
        yuanxu-module-config-validation-receipts)

(def (yuanxu-module-find-schema schemas option-id-value)
  (find (lambda (schema)
          (yuanxu-module-kind=? (.ref schema 'id)
                                  option-id-value))
        schemas))

(def (yuanxu-module-missing-schema-receipt config)
  (missing-schema-receipt (.ref config 'id) (.ref config 'source-module)))

(def (missing-schema-receipt option-id contributor)
  (.o id: option-id
      source-module: contributor
      valid?: #f
      code: 'missing-schema
      messages: '("option schema is not declared")
      metadata: '()))

(def (yuanxu-module-option-schema-validation-receipt schema config)
  (validate-option schema config (.ref config 'id) (.ref config 'source-module)))

(def (validate-option schema config option-id contributor)
  (def issues
    (checked-issues
      (diagnose-value
        (yuanxu-module-option-schema-contract schema)
        (object<-alist
          (list (cons (string->symbol option-id)
                      (.ref config 'value))))
        '())))
  (def annotations (yuanxu-module-option-schema-metadata schema))
  ;; This is a diagnostic projection, not accepted Contract/publication evidence.
  (.o id: option-id
      source-module: contributor
      valid?: (null? issues)
      code: (if (null? issues) 'ok (.ref (car issues) 'kind))
      messages: issues
      metadata: annotations))

;; Preserve input order while traversing only once; schema-ref is supplied by
;; the owner of the concrete Module Interface or descriptor.
(def (yuanxu-module-options-validate schema-ref configs)
  (let loop ((remaining configs) (receipts-rev '()))
    (if (null? remaining)
      (reverse receipts-rev)
      (let* ((config (car remaining))
             ;; Keep routing and diagnostic attribution together across callbacks.
             (option-id (.ref config 'id))
             (contributor (.ref config 'source-module))
             (schema (schema-ref option-id)))
        (loop (cdr remaining)
              (cons (if schema
                      (validate-option schema config option-id contributor)
                      (missing-schema-receipt option-id contributor))
                    receipts-rev))))))

;; Read input names before author diagnostics can change the candidate's shape.
;; The owner supplies effective Slot metadata after diagnostics are grouped.
(def (yuanxu-module-config-validation-receipts declaration schema-ref config owner)
  (def names (if (object? config) (.all-slots config) '()))
  (def issues (checked-issues (diagnose-value declaration config '())))
  (def seen (make-hash-table))
  (def grouped (make-hash-table))
  (def absent-rev '())
  (for-each (lambda (name) (hash-put! seen name #t)) names)
  (for-each
    (lambda (issue)
      (def path (.ref issue 'path))
      (def name (and (pair? path) (symbol? (car path)) (car path)))
      (when (and name (not (hash-get seen name)))
        (hash-put! seen name #t)
        (set! absent-rev (cons name absent-rev)))
      ;; Each group keeps its first code and the original issues in reverse order.
      ;; #f owns whole-Record issues.
      (hash-update! grouped name
        (lambda (group)
          (if group
            (cons (car group) (cons issue (cdr group)))
            (list (.ref issue 'kind) issue)))
        #f))
    issues)
  (append
    (map (lambda (name)
           (def option-id (symbol->string name))
           (def field (schema-ref option-id))
           (def group (hash-get grouped name))
           (if (and (not field) (not group))
             (missing-schema-receipt option-id owner)
             (let ((annotations (yuanxu-module-object-ref/default field 'metadata '()))
                   (failures (if group (reverse (cdr group)) '())))
               (.o id: option-id source-module: owner
                   valid?: (not group)
                   code: (if group (car group) 'ok)
                   messages: failures metadata: annotations))))
         (append names (reverse absent-rev)))
    (if (hash-key? grouped #f)
      (let* ((group (hash-ref grouped #f)) (failures (reverse (cdr group))))
        (list (.o id: #f source-module: owner valid?: #f
                  code: (car group) messages: failures metadata: '())))
      '())))
