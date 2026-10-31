;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: constant-slot lookup and field indexing for POO object support;
;;; inheritance resolution remains owned by object.ss.
(import :gerbil/core
        (only-in :clan/poo/object
                 $constant-slot-spec
                 $constant-slot-spec-value
                 $constant-slot-spec?
                 .ref
                 object-slots)
        :yuanxu/module-system/schema/support/contracts)

(export yuanxu-module-object-constant-slot
        +yuanxu-module-object-slot-missing+
        yuanxu-module-object-constant-slot-ref/default
        yuanxu-module-object-constant-slot-ref
        yuanxu-module-object-field-identity
        yuanxu-module-object-field-index
        yuanxu-module-object-identity-hash-ref
        yuanxu-module-object-field-set)

;; Boundary: slot lookup and field indexing helpers stay independent from
;; object inheritance resolution, which remains in object.ss.
;; : (-> Symbol Object ConstantSlotSpec)
(def (yuanxu-module-object-constant-slot key value)
  (let (spec ($constant-slot-spec value))
    `(,key . ,spec)))

;; : MissingSlotSentinel
(def +yuanxu-module-object-slot-missing+
  (list 'yuanxu-module-object-slot-missing))

;; yuanxu-module-object-constant-slot-ref/default
;;   : (-> POOObject Symbol Object Object)
;;   | doc m%
;;       Read a constant POO slot without forcing dynamic slot fallback.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-module-object-constant-slot-ref/default object 'name #f)
;;       ;; => the constant value, or #f
;;       ```
;;     %
(def (yuanxu-module-object-constant-slot-ref/default object key default)
  (match (assq key (object-slots object))
    (#f default)
    ([_ . spec]
     (if ($constant-slot-spec? spec)
       ($constant-slot-spec-value spec)
       default))))

;; : (-> POOObject Symbol Object)
(def (yuanxu-module-object-constant-slot-ref object key)
  (let (value (yuanxu-module-object-constant-slot-ref/default
               object
               key
               +yuanxu-module-object-slot-missing+))
    (if (eq? value +yuanxu-module-object-slot-missing+)
      (.ref object key)
      value)))

;; : (-> FieldContractLike Symbol)
(def (yuanxu-module-object-field-identity field)
  (if (yuanxu-module-field-contract? field)
    (yuanxu-module-field-contract-identity field)
    field))

;; : (-> [FieldContractLike] HashTable)
(def (yuanxu-module-object-field-index fields)
  (let (index (make-hash-table))
    (for-each
     (lambda (field)
       (let (identity (yuanxu-module-object-field-identity field))
         (if (yuanxu-module-object-identity-hash-ref index identity)
           index
           (hash-put! index identity field))))
     fields)
    index))

;; : (-> HashTable Symbol Object)
(def (yuanxu-module-object-identity-hash-ref table identity)
  (hash-get table identity))

;; : (-> [FieldContractLike] FieldContractLike [FieldContractLike])
(def (yuanxu-module-object-field-set fields field)
  (let (field-identity (yuanxu-module-object-field-identity field))
    (cond ((null? fields) (list field))
          ((equal? (yuanxu-module-object-field-identity (car fields))
                   field-identity)
           (cons field (cdr fields)))
          (else
           (cons (car fields)
                 (yuanxu-module-object-field-set (cdr fields) field))))))
