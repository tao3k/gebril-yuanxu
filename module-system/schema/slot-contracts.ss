;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: reusable POO-native slot schemas for module Type/Contract owners.
;;; Invariant: schemas are ordinary POO values; alists exist only as receipts.

(import (only-in :clan/poo/object .cc .o .ref)
        (only-in :clan/poo/mop element? raise-type-error)
        (only-in :std/list/list filter-map)
        (only-in :yuanxu/types
                 yuanxu-predicate-contract
                 yuanxu-predicate-type))

(export yuanxu-contract-value-type
        yuanxu-contract-slot
        yuanxu-contract-slot-key
        yuanxu-contract-slot-name
        yuanxu-contract-slot-type
        yuanxu-contract-slot-report-kind
        yuanxu-contract-slot-predicate-key
        yuanxu-contract-slot-required?
        yuanxu-contract-slot-metadata
        yuanxu-native-contract
        yuanxu-native-contract-key
        yuanxu-native-contract-owner
        yuanxu-native-contract-object-kind
        yuanxu-native-contract-slots
        yuanxu-native-contract-metadata
        yuanxu-contract-slot->alist
        yuanxu-native-contract->alist
        yuanxu-contract-check-slot!)

;; report-kind is receipt metadata only.  Runtime admission always dispatches
;; through the native Type protocol and never through this symbolic label.
(def (yuanxu-contract-value-type identity predicate report-kind
                                   . maybe-predicate-key)
  (.cc (yuanxu-predicate-type identity predicate)
       'report-kind report-kind
       'predicate-key
       (if (null? maybe-predicate-key) identity (car maybe-predicate-key))))

(def (yuanxu-contract-slot key-value slot-value value-type-value
                             required-value metadata-value)
  (.o kind: 'yuanxu.contract.slot-schema
      key: key-value
      slot: slot-value
      value-type: value-type-value
      required?: (if required-value #t #f)
      metadata: metadata-value))

(def (yuanxu-contract-slot-name slot-contract)
  (.ref slot-contract 'slot))

(def (yuanxu-contract-slot-key slot-contract)
  (.ref slot-contract 'key))

(def (yuanxu-contract-slot-type slot-contract)
  (.ref slot-contract 'value-type))

(def (yuanxu-contract-slot-report-kind slot-contract)
  (.ref (yuanxu-contract-slot-type slot-contract) 'report-kind))

(def (yuanxu-contract-slot-predicate-key slot-contract)
  (.ref (yuanxu-contract-slot-type slot-contract) 'predicate-key))

(def (yuanxu-contract-slot-required? slot-contract)
  (.ref slot-contract 'required?))

(def (yuanxu-contract-slot-metadata slot-contract)
  (.ref slot-contract 'metadata))

(def (yuanxu-contract-obligations slots slot-present? slot-ref)
  (lambda (candidate _context)
    (let (slot-failure
          (lambda (slot-name reason-value)
            (.o kind: 'yuanxu.contract.slot-failure
                slot: slot-name
                reason: reason-value)))
      (filter-map
       (lambda (slot-contract)
         (let* ((slot-name (yuanxu-contract-slot-name slot-contract))
                (required? (yuanxu-contract-slot-required? slot-contract))
                (present? (slot-present? candidate slot-name)))
           (cond
            ((and required? (not present?))
             (slot-failure slot-name 'required-slot-absent))
            ((and present?
                  (not (element? (yuanxu-contract-slot-type slot-contract)
                                 (slot-ref candidate slot-name))))
             (slot-failure slot-name 'slot-type-rejected))
            (else #f))))
       slots))))

(def (yuanxu-native-contract identity owner object-kind predicate
                               slots slot-present? slot-ref metadata)
  (.cc (yuanxu-predicate-contract
        identity
        predicate
        (yuanxu-contract-obligations slots slot-present? slot-ref))
       'owner owner
       'object-kind object-kind
       'slots slots
       'metadata metadata))

(def (yuanxu-native-contract-key contract)
  (.ref contract 'identity))

(def (yuanxu-native-contract-owner contract)
  (.ref contract 'owner))

(def (yuanxu-native-contract-object-kind contract)
  (.ref contract 'object-kind))

(def (yuanxu-native-contract-slots contract)
  (.ref contract 'slots))

(def (yuanxu-native-contract-metadata contract)
  (.ref contract 'metadata))

(def (yuanxu-contract-slot->alist slot-contract)
  (list (cons 'key (yuanxu-contract-slot-key slot-contract))
        (cons 'slot (yuanxu-contract-slot-name slot-contract))
        (cons 'value-kind
              (yuanxu-contract-slot-report-kind slot-contract))
        (cons 'predicate (yuanxu-contract-slot-predicate-key slot-contract))
        (cons 'required? (yuanxu-contract-slot-required? slot-contract))
        (cons 'metadata (yuanxu-contract-slot-metadata slot-contract))))

(def (yuanxu-native-contract->alist contract)
  (list (cons 'key (yuanxu-native-contract-key contract))
        (cons 'owner (yuanxu-native-contract-owner contract))
        (cons 'object-kind (yuanxu-native-contract-object-kind contract))
        (cons 'slots
              (map yuanxu-contract-slot->alist
                   (yuanxu-native-contract-slots contract)))
        (cons 'metadata (yuanxu-native-contract-metadata contract))))

(def (yuanxu-contract-check-slot! slot-contract value)
  (if (element? (yuanxu-contract-slot-type slot-contract) value)
    value
    (raise-type-error (yuanxu-contract-slot-type slot-contract) value)))
