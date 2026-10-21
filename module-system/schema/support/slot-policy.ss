;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: pure, ordered field-value policies. POO owns inheritance;
;;; explicit append/prepend/remove are value operations, not module merging.

(import :gerbil/core)

(export yuanxu-module-slot-apply-policy
        yuanxu-module-slot-value-index
        yuanxu-module-slot-append-distinct
        yuanxu-module-slot-append-distinct/indexed
        yuanxu-module-slot-remove-elements
        yuanxu-module-slot-list-value
        yuanxu-module-slot-policy?)

;; : (-> [PooModuleSlotValue] HashTable)
(def (yuanxu-module-slot-value-index values)
  (let (index (make-hash-table))
    (for-each
     (lambda (value)
       (hash-put! index value #t))
     values)
    index))

;;; Distinct append preserves the base list and indexes only when extra values
;;; need admission. The indexed entry is reused by sparse field resolution.
;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-module-slot-append-distinct base extra)
  (if (null? extra)
    base
    (yuanxu-module-slot-append-distinct/indexed
     base extra (yuanxu-module-slot-value-index base))))

;; : (-> [PooModuleSlotValue] HashTable [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-module-slot-append-distinct-added/rev extra seen added-rev)
  (append
   (reverse
    (filter-map
     (lambda (value)
       (and (not (hash-get seen value))
            (begin
              (hash-put! seen value #t)
              value)))
     extra))
   added-rev))

;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] HashTable [PooModuleSlotValue])
(def (yuanxu-module-slot-append-distinct/indexed base extra seen)
  (let (added
        (yuanxu-module-slot-append-distinct-added/rev extra seen '()))
    (if (null? added)
      base
      (append base (reverse added)))))

;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-module-slot-remove-elements values removed)
  (if (null? removed)
    values
    (let (removed-index (yuanxu-module-slot-value-index removed))
      (filter (lambda (value)
                (not (hash-get removed-index value)))
              values))))

;; : (-> PooModuleSlotValue [PooModuleSlotValue])
(def (yuanxu-module-slot-list-value value)
  (cond ((null? value) '())
        ((list? value) value)
        (else (list value))))

;; : (-> Symbol Boolean)
(def (yuanxu-module-slot-policy? policy)
  (or (eq? policy 'override)
      (eq? policy 'append)
      (eq? policy 'prepend)
      (eq? policy 'remove)))

;;; Unknown policies leave the current value unchanged. Contract admission
;;; rejects invalid user rows before they reach this pure operation.
;; : (-> Symbol PooModuleSlotValue PooModuleSlotValue PooModuleSlotValue)
(def (yuanxu-module-slot-apply-policy policy current value)
  (cond
   ((eq? policy 'override) value)
   ((eq? policy 'append)
    (yuanxu-module-slot-append-distinct
     (yuanxu-module-slot-list-value current)
     (yuanxu-module-slot-list-value value)))
   ((eq? policy 'prepend)
    (yuanxu-module-slot-append-distinct
     (yuanxu-module-slot-list-value value)
     (yuanxu-module-slot-list-value current)))
   ((eq? policy 'remove)
    (yuanxu-module-slot-remove-elements
     (yuanxu-module-slot-list-value current)
     (yuanxu-module-slot-list-value value)))
   (else current)))
