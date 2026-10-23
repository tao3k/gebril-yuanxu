;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: structured type facts for Yuanxu validation layers.
;;; Invariant: facts are Scheme control-plane data; Lean and runtime payloads
;;; are final projections, not semantic owners.

(import (only-in :yuanxu/module-system/schema/slot-contracts
                 yuanxu-contract-slot-key
                 yuanxu-contract-slot-name
                 yuanxu-contract-slot-report-kind
                 yuanxu-contract-slot-predicate-key
                 yuanxu-contract-slot-required?
                 yuanxu-contract-slot-metadata
                 yuanxu-object-contract-key
                 yuanxu-object-contract-owner
                 yuanxu-object-contract-object-kind
                 yuanxu-object-contract-slots
                 yuanxu-object-contract-metadata))

(export make-yuanxu-type-fact-contract
        yuanxu-type-fact-contract?
        yuanxu-type-fact-contract-key
        yuanxu-type-fact-contract-kind
        yuanxu-type-fact-contract-owner
        yuanxu-type-fact-contract-name
        yuanxu-type-fact-contract-source-slot
        yuanxu-type-fact-contract-value-kind
        yuanxu-type-fact-contract-polarity
        yuanxu-type-fact-contract-metadata
        yuanxu-type-fact
        yuanxu-type-fact-contract->alist
        make-yuanxu-lean-fact-contract
        yuanxu-lean-fact-contract?
        yuanxu-lean-fact-contract-key
        yuanxu-lean-fact-contract-kind
        yuanxu-lean-fact-contract-lean-owner
        yuanxu-lean-fact-contract-lean-name
        yuanxu-lean-fact-contract-source-slot
        yuanxu-lean-fact-contract-polarity
        yuanxu-lean-fact-contract-metadata
        yuanxu-lean-fact
        yuanxu-lean-fact-contract->alist
        yuanxu-contract-required-polarity
        yuanxu-contract-slot-fact-metadata
        yuanxu-contract-slot->type-fact
        yuanxu-object-contract->type-facts
        yuanxu-contract-slot->lean-fact-contract
        yuanxu-object-contract->lean-fact-contracts)

;; yuanxu-type-fact-contract
;;   : (-> Symbol Symbol Symbol Symbol Symbol Symbol Symbol Alist YuanxuTypeFactContract)
;;   | doc m%
;;       Fixed Scheme-side type fact row. The generated constructor and accessors
;;       stay internal to the validation layer; runtime and Lean consumers receive
;;       only the explicit alist projection.
;;     %
(defstruct yuanxu-type-fact-contract
  (key
   kind
   owner
   name
   source-slot
   value-kind
   polarity
   metadata)
  transparent: #t)

;; : (-> Symbol Symbol Symbol Symbol Symbol Symbol Symbol [Alist] YuanxuTypeFactContract)
(def (yuanxu-type-fact key kind owner name source-slot value-kind polarity
                         . maybe-metadata)
  (make-yuanxu-type-fact-contract
   key
   kind
   owner
   name
   source-slot
   value-kind
   polarity
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; : (-> YuanxuTypeFactContract Alist)
(def (yuanxu-type-fact-contract->alist fact)
  (list
   (cons 'key (yuanxu-type-fact-contract-key fact))
   (cons 'kind (yuanxu-type-fact-contract-kind fact))
   (cons 'owner (yuanxu-type-fact-contract-owner fact))
   (cons 'name (yuanxu-type-fact-contract-name fact))
   (cons 'source-slot (yuanxu-type-fact-contract-source-slot fact))
   (cons 'value-kind (yuanxu-type-fact-contract-value-kind fact))
   (cons 'polarity (yuanxu-type-fact-contract-polarity fact))
   (cons 'metadata (yuanxu-type-fact-contract-metadata fact))))

;; yuanxu-lean-fact-contract
;;   : (-> Symbol Symbol Symbol Symbol Symbol Symbol Alist YuanxuLeanFactContract)
;;   | doc m%
;;       Fixed Lean fact contract row. It records the Lean owner/name separately
;;       from the Scheme source slot so projection can remain explicit.
;;     %
(defstruct yuanxu-lean-fact-contract
  (key
   kind
   lean-owner
   lean-name
   source-slot
   polarity
   metadata)
  transparent: #t)

;; : (-> Symbol Symbol Symbol Symbol Symbol Symbol [Alist] YuanxuLeanFactContract)
(def (yuanxu-lean-fact key kind lean-owner lean-name source-slot polarity
                         . maybe-metadata)
  (make-yuanxu-lean-fact-contract
   key
   kind
   lean-owner
   lean-name
   source-slot
   polarity
   (if (null? maybe-metadata) '() (car maybe-metadata))))

;; : (-> YuanxuLeanFactContract Alist)
(def (yuanxu-lean-fact-contract->alist fact)
  (list
   (cons 'key (yuanxu-lean-fact-contract-key fact))
   (cons 'kind (yuanxu-lean-fact-contract-kind fact))
   (cons 'lean-owner (yuanxu-lean-fact-contract-lean-owner fact))
   (cons 'lean-name (yuanxu-lean-fact-contract-lean-name fact))
   (cons 'source-slot (yuanxu-lean-fact-contract-source-slot fact))
   (cons 'polarity (yuanxu-lean-fact-contract-polarity fact))
   (cons 'metadata (yuanxu-lean-fact-contract-metadata fact))))

;; yuanxu-contract-required-polarity
;;   : (-> Boolean Symbol)
;;   | doc m%
;;       Convert a slot contract required flag into the polarity used by
;;       type-fact and Lean-fact projections.
;;       # Examples
;;       (yuanxu-contract-required-polarity #t)
;;       # Result
;;       'positive
;;     %
(def (yuanxu-contract-required-polarity required?)
  (if required? 'positive 'optional))

;; yuanxu-contract-slot-fact-metadata
;;   : (-> YuanxuObjectTypeContract YuanxuSlotContract Alist)
;;   | doc m%
;;       Preserve the executable contract identity as projection metadata while
;;       keeping the projected fact itself non-executable.
;;       # Examples
;;       (yuanxu-contract-slot-fact-metadata object-contract slot-contract)
;;       # Result
;;       An alist containing object contract, owner, predicate, and slot metadata.
;;     %
(def (yuanxu-contract-slot-fact-metadata object-contract slot-contract)
  (append
   (list
    (cons 'object-contract
          (yuanxu-object-contract-key object-contract))
    (cons 'contract-owner
          (yuanxu-object-contract-owner object-contract))
    (cons 'object-metadata
          (yuanxu-object-contract-metadata object-contract))
    (cons 'predicate
          (yuanxu-contract-slot-predicate-key slot-contract))
    (cons 'required?
          (yuanxu-contract-slot-required? slot-contract)))
   (yuanxu-contract-slot-metadata slot-contract)))

;; yuanxu-contract-slot->type-fact
;;   : (-> YuanxuObjectTypeContract YuanxuSlotContract YuanxuTypeFactContract)
;;   | doc m%
;;       Project one structured slot contract into a type fact row. The fact
;;       records the POO object kind, source slot, value kind, and polarity.
;;       # Examples
;;       (yuanxu-contract-slot->type-fact object-contract slot-contract)
;;       # Result
;;       A non-executable type fact contract row.
;;     %
(def (yuanxu-contract-slot->type-fact object-contract slot-contract)
  (yuanxu-type-fact
   (yuanxu-contract-slot-key slot-contract)
   'slot-contract
   (yuanxu-object-contract-object-kind object-contract)
   (yuanxu-contract-slot-name slot-contract)
   (yuanxu-contract-slot-name slot-contract)
   (yuanxu-contract-slot-report-kind slot-contract)
   (yuanxu-contract-required-polarity
    (yuanxu-contract-slot-required? slot-contract))
   (yuanxu-contract-slot-fact-metadata object-contract slot-contract)))

;; yuanxu-object-contract->type-facts
;;   : (-> YuanxuContract [YuanxuTypeFactContract])
;;   | doc m%
;;       Project every native slot schema in a Contract into stable type facts.
;;       This is a one-way proof projection from native descriptors.
;;       # Examples
;;       (yuanxu-object-contract->type-facts receipt-contract)
;;       # Result
;;       A list of type fact contract rows.
;;     %
(def (yuanxu-object-contract->type-facts object-contract)
  (map (lambda (slot-contract)
         (yuanxu-contract-slot->type-fact object-contract slot-contract))
       (yuanxu-object-contract-slots object-contract)))

;; yuanxu-contract-slot->lean-fact-contract
;;   : (-> YuanxuObjectTypeContract YuanxuSlotContract YuanxuLeanFactContract)
;;   | doc m%
;;       Project one slot contract into a Lean fact contract request. Scheme
;;       names the proof address; Lean remains an external verification target.
;;       # Examples
;;       (yuanxu-contract-slot->lean-fact-contract object-contract slot-contract)
;;       # Result
;;       A non-executable Lean fact contract row.
;;     %
(def (yuanxu-contract-slot->lean-fact-contract object-contract slot-contract)
  (yuanxu-lean-fact
   (yuanxu-contract-slot-key slot-contract)
   'slot-contract
   (yuanxu-object-contract-object-kind object-contract)
   (yuanxu-contract-slot-name slot-contract)
   (yuanxu-contract-slot-name slot-contract)
   (yuanxu-contract-required-polarity
    (yuanxu-contract-slot-required? slot-contract))
   (yuanxu-contract-slot-fact-metadata object-contract slot-contract)))

;; yuanxu-object-contract->lean-fact-contracts
;;   : (-> YuanxuContract [YuanxuLeanFactContract])
;;   | doc m%
;;       Project every slot contract in an object contract into Lean fact
;;       contract requests. The output is data for proof tooling, not execution.
;;       # Examples
;;       (yuanxu-object-contract->lean-fact-contracts receipt-contract)
;;       # Result
;;       A list of Lean fact contract rows.
;;     %
(def (yuanxu-object-contract->lean-fact-contracts object-contract)
  (map (lambda (slot-contract)
         (yuanxu-contract-slot->lean-fact-contract object-contract
                                                     slot-contract))
       (yuanxu-object-contract-slots object-contract)))
