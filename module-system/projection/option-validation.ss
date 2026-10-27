;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure option validation over Core Module POO values. Descriptor-specific
;;; schema discovery remains with the product adapter.

(import (only-in :yuanxu/module-system/config yuanxu-module-kind=? yuanxu-module-object-ref/default)
        (only-in :clan/poo/object .o .ref .all-slots object? object<-alist)
        (only-in :clan/poo/value-diagnostics diagnose-value)
        (only-in :clan/poo/object-diagnostics checked-issues)
        :yuanxu/module-system/projection/option-objects)

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
  (def option-id (.ref config 'id))
  (def contributor (.ref config 'source-module))
  (.o id: option-id
      source-module: contributor
        valid?: #f
        code: 'missing-schema
        messages: '("option schema is not declared")
        metadata: '()))

(def (yuanxu-module-option-schema-validation-receipt schema config)
  (def issues
    (checked-issues
      (diagnose-value
        (yuanxu-module-option-schema-contract schema)
        (object<-alist
          (list (cons (string->symbol (.ref config 'id))
                      (.ref config 'value))))
        '())))
  ;; Preserve attribution/annotation observation at production, not first reporting.
  (def option-id (.ref config 'id))
  (def contributor (.ref config 'source-module))
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
             (schema (schema-ref (.ref config 'id))))
        (loop (cdr remaining)
              (cons (if schema
                      (yuanxu-module-option-schema-validation-receipt
                       schema config)
                      (yuanxu-module-missing-schema-receipt config))
                    receipts-rev))))))

;; Diagnose the actual Record once, preserving missing fields and whole-object
;; membership. schema-ref is the owner's existing effective-Slot index, not a
;; second field declaration. The tables below only group the returned issues.
(def (yuanxu-module-config-validation-receipts declaration schema-ref config owner)
  (def issues (checked-issues (diagnose-value declaration config '())))
  (def names (if (object? config) (.all-slots config) '()))
  (def seen (make-hash-table))
  (def grouped (make-hash-table))
  (def absent-rev '())
  (def root-rev '())
  (for-each (lambda (name) (hash-put! seen name #t)) names)
  (for-each
    (lambda (issue)
      (def path (.ref issue 'path))
      (if (and (pair? path) (symbol? (car path)))
        (let (name (car path))
          (unless (hash-get seen name)
            (hash-put! seen name #t)
            (set! absent-rev (cons name absent-rev)))
          (hash-update! grouped name (cut cons issue <>) '()))
        (set! root-rev (cons issue root-rev))))
    issues)
  (append
    (map (lambda (name)
           (def option-id (symbol->string name))
           (def field (schema-ref option-id))
           (def failures (reverse (hash-ref grouped name '())))
           (if (and (not field) (null? failures))
             (yuanxu-module-missing-schema-receipt
               (.o id: option-id source-module: owner))
             (let (annotations (yuanxu-module-object-ref/default field 'metadata '()))
               (.o id: option-id source-module: owner
                   valid?: (null? failures)
                   code: (if (null? failures) 'ok (.ref (car failures) 'kind))
                   messages: failures metadata: annotations))))
         (append names (reverse absent-rev)))
    (if (null? root-rev) '()
      (let (failures (reverse root-rev))
        ;; No invented field name for a whole-value refusal.
        (list (.o id: #f source-module: owner valid?: #f
                  code: (.ref (car failures) 'kind)
                  messages: failures metadata: '()))))))
