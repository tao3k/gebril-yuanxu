;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: reusable POO-native slot schemas for module Type/Contract owners.
;;; Invariant: schemas are ordinary POO values; alists exist only as receipts.

(import (only-in :clan/poo/object .all-slots .cc .o .ref .slot?)
        (only-in :clan/poo/mop Type Type. validate)
        (only-in :clan/poo/type Record))

(export yuanxu-contract-value-type
        yuanxu-contract-slot
        yuanxu-contract-slot-key
        yuanxu-contract-slot-name
        yuanxu-contract-slot-type
        yuanxu-contract-slot-report-kind
        yuanxu-contract-slot-predicate-key
        yuanxu-contract-slot-required?
        yuanxu-contract-slot-metadata
        yuanxu-object-contract
        yuanxu-object-contract-key
        yuanxu-object-contract-owner
        yuanxu-object-contract-object-kind
        yuanxu-object-contract-slots
        yuanxu-object-contract-metadata
        yuanxu-contract-slot->alist
        yuanxu-object-contract->alist
        yuanxu-contract-check-slot!)

;; report-kind is receipt metadata only.  Runtime admission always dispatches
;; through the native Type protocol and never through this symbolic label.
(def (yuanxu-contract-value-type identity predicate report-kind
                                   . maybe-predicate-key)
  (.cc Type.
       'identity identity
       'sexp identity
       '.element? predicate
       'report-kind report-kind
       'predicate-key
       (if (null? maybe-predicate-key) identity (car maybe-predicate-key))))

(def (yuanxu-contract-slot key-value slot-value value-type-value
                             required-value metadata-value)
  (validate Type value-type-value)
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
  (let (type (yuanxu-contract-slot-type slot-contract))
    (if (.slot? type 'report-kind) (.ref type 'report-kind) 'Type)))

(def (yuanxu-contract-slot-predicate-key slot-contract)
  (let (type (yuanxu-contract-slot-type slot-contract))
    (if (.slot? type 'predicate-key) (.ref type 'predicate-key) 'native-type)))

(def (yuanxu-contract-slot-required? slot-contract)
  (.ref slot-contract 'required?))

(def (yuanxu-contract-slot-metadata slot-contract)
  (.ref slot-contract 'metadata))

;; Record owns required/optional presence and recursive Type normalization.
;; Extend its native membership protocol with the domain predicate. Its inherited
;; Class validator rechecks that predicate on the final normalized receiver.
(def (yuanxu-object-contract identity-value owner-value object-kind-value predicate-value
                             schemas metadata-value)
  (let (fields
         (apply Record
           (apply append
             (map (lambda (schema)
                    (list (make-keyword (yuanxu-contract-slot-name schema))
                          (list (yuanxu-contract-slot-type schema)
                                optional: (not (yuanxu-contract-slot-required? schema)))))
                  schemas))))
    (.o inherit: (list fields)
        identity: identity-value
        owner: owner-value
        object-kind: object-kind-value
        slot-schemas: schemas
        metadata: metadata-value
        (.element? (inherited)
          (lambda (candidate)
            (and ((inherited) candidate) (predicate-value candidate)))))))

(def (yuanxu-object-contract-key contract)
  (.ref contract 'identity))

(def (yuanxu-object-contract-owner contract)
  (.ref contract 'owner))

(def (yuanxu-object-contract-object-kind contract)
  (.ref contract 'object-kind))

(def (yuanxu-object-contract-slots contract)
  (let* ((schemas (.ref contract 'slot-schemas))
         (effective (.ref contract 'effective-slots))
         (native-names (.all-slots effective))
         (schema-names (map yuanxu-contract-slot-name schemas)))
    ;; Receipts must describe the current native Slot types and optional policy.
    ;; A native field addition also needs receipt metadata; refuse incomplete
    ;; projection rather than publishing stale type facts from an ancestor.
    (unless (and (= (length schemas) (length native-names))
                 (andmap (cut memq <> schema-names) native-names))
      (error "native contract fields require complete receipt metadata"))
    (map (lambda (schema)
           (let (field (.ref effective (yuanxu-contract-slot-name schema)))
             (.cc schema 'value-type (.ref field 'type)
                         'required? (not (.ref field 'optional))))) schemas)))

(def (yuanxu-object-contract-metadata contract)
  (.ref contract 'metadata))

(def (yuanxu-contract-slot->alist slot-contract)
  (list (cons 'key (yuanxu-contract-slot-key slot-contract))
        (cons 'slot (yuanxu-contract-slot-name slot-contract))
        (cons 'value-kind
              (yuanxu-contract-slot-report-kind slot-contract))
        (cons 'predicate (yuanxu-contract-slot-predicate-key slot-contract))
        (cons 'required? (yuanxu-contract-slot-required? slot-contract))
        (cons 'metadata (yuanxu-contract-slot-metadata slot-contract))))

(def (yuanxu-object-contract->alist contract)
  (list (cons 'key (yuanxu-object-contract-key contract))
        (cons 'owner (yuanxu-object-contract-owner contract))
        (cons 'object-kind (yuanxu-object-contract-object-kind contract))
        (cons 'slots
              (map yuanxu-contract-slot->alist
                   (yuanxu-object-contract-slots contract)))
        (cons 'metadata (yuanxu-object-contract-metadata contract))))

(def (yuanxu-contract-check-slot! slot-contract value)
  (validate (yuanxu-contract-slot-type slot-contract) value))
