;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Boundary: native POO extension-operation prototypes and dispatch.
;;; Each operation family owns application and batching behavior as slots;
;;; graph node helpers remain pure values in payload-operations.ss.

(import :gerbil/core
        (only-in :clan/poo/object .mix .o .ref)
        (only-in :clan/poo/mop .defgeneric)
        :yuanxu/graph/contribution
        :yuanxu/graph/payload-operations)

(export yuanxu-graph-operation-prototype
        yuanxu-graph-slot-override-prototype
        yuanxu-graph-slot-append-prototype
        yuanxu-graph-slot-prepend-prototype
        yuanxu-graph-slot-remove-prototype
        yuanxu-graph-node-extend-prototype
        yuanxu-graph-node-remove-prototype
        yuanxu-graph-slot-override
        yuanxu-graph-slot-append
        yuanxu-graph-slot-prepend
        yuanxu-graph-slot-remove
        yuanxu-graph-node-extend
        yuanxu-graph-node-remove
        yuanxu-graph-apply-operation
        yuanxu-graph-operation-state
        yuanxu-graph-local-operation?
        yuanxu-graph-node-extend-operation?
        yuanxu-graph-slot-append-operation?
        yuanxu-graph-flush-slot-append
        yuanxu-graph-coalesce-slot-appends)

;;; Ordinary operation application flushes pending batches before invoking the
;;; receiver-owned method. Specialized prototypes replace only this stage slot.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (yuanxu-graph-stage-operation operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [(yuanxu-graph-operation-apply
       operation
       (yuanxu-graph-flush-pending current
                                                pending-node-extends
                                                pending-slot-overrides))
      '()
      '()])))

;;; Node extension batches preserve encounter order until the merge boundary.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (yuanxu-graph-stage-node-extend operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [current
      (cons (yuanxu-graph-operation-node operation)
            pending-node-extends)
      pending-slot-overrides])))

;;; Slot overrides batch as key/value rows and use the common deterministic
;;; slot merge only when an operation family requires a flush.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (yuanxu-graph-stage-slot-override operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [current
      pending-node-extends
      (cons (cons (yuanxu-graph-operation-slot operation)
                  (yuanxu-graph-operation-value operation))
            pending-slot-overrides)])))

;;; The base prototype supplies total identity behavior and common semantic
;;; facets. Concrete operation prototypes refine `.apply` and, when batchable,
;;; `.stage`; adding a family therefore does not extend a central action switch.
(def yuanxu-graph-operation-prototype
  (.o (:: self)
      kind: yuanxu-graph-operation-kind
      action: 'identity
      local?: #f
      node-extend?: #f
      slot-append?: #f
      (.apply (lambda (node) node))
      (.stage
       (lambda (state)
         (yuanxu-graph-stage-operation self state)))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-slot-override-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'slot-override
      local?: #t
      (.apply
       (lambda (node)
         (yuanxu-graph-root-replace
          node
          (yuanxu-graph-alist-set
           (yuanxu-graph-root-payload node)
           (yuanxu-graph-operation-slot self)
           (yuanxu-graph-operation-value self))
          (yuanxu-graph-root-children node))))
      (.stage
       (lambda (state)
         (yuanxu-graph-stage-slot-override self state)))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-slot-append-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'slot-append
      local?: #t
      slot-append?: #t
      (.apply
       (lambda (node)
         (yuanxu-graph-apply-slot-list-op node self #t)))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-slot-prepend-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'slot-prepend
      local?: #t
      (.apply
       (lambda (node)
         (yuanxu-graph-apply-slot-list-op node self #f)))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-slot-remove-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'slot-remove
      local?: #t
      (.apply
       (lambda (node)
         (let* ((slot (yuanxu-graph-operation-slot self))
                (current
                 (yuanxu-graph-list-value
                  (yuanxu-graph-alist-ref/default
                   (yuanxu-graph-root-payload node) slot '())))
                (removed
                 (yuanxu-graph-list-value
                  (yuanxu-graph-operation-value self))))
           (yuanxu-graph-root-replace
            node
            (yuanxu-graph-alist-set
             (yuanxu-graph-root-payload node)
             slot
             (yuanxu-graph-remove-elements current removed))
            (yuanxu-graph-root-children node)))))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-node-extend-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'node-extend
      node-extend?: #t
      (.apply
       (lambda (node)
         (yuanxu-graph-root-replace
          node
          (yuanxu-graph-root-payload node)
          (yuanxu-graph-children-merge-one
           (yuanxu-graph-root-children node)
           (yuanxu-graph-operation-node self)))))
      (.stage
       (lambda (state)
         (yuanxu-graph-stage-node-extend self state)))))

;; : PooGraphOperationPrototype
(def yuanxu-graph-node-remove-prototype
  (.o (:: self yuanxu-graph-operation-prototype)
      action: 'node-remove
      (.apply
       (lambda (node)
         (yuanxu-graph-root-replace
          node
          (yuanxu-graph-root-payload node)
          (yuanxu-graph-children-remove
           (yuanxu-graph-root-children node)
           (yuanxu-graph-operation-target self)))))))

;;; Dynamic payloads are constant defaults on a static operation prototype.
;;; This preserves inspectable slots without rebuilding method closures per row.
;; : (-> PooGraphOperationPrototype MaybeSymbol PooModuleSlotValue MaybeYuanxuGraph MaybeSymbol PooGraphOperation)
(def (yuanxu-graph-operation-instance prototype slot value node target)
  (.mix prototype
    defaults: (list (cons 'slot slot)
                    (cons 'value value)
                    (cons 'node node)
                    (cons 'target target))))

;; : (-> Symbol PooModuleSlotValue PooGraphOperation)
(def (yuanxu-graph-slot-override slot value)
  (yuanxu-graph-operation-instance
   yuanxu-graph-slot-override-prototype slot value #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (yuanxu-graph-slot-append slot values)
  (yuanxu-graph-operation-instance
   yuanxu-graph-slot-append-prototype slot values #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (yuanxu-graph-slot-prepend slot values)
  (yuanxu-graph-operation-instance
   yuanxu-graph-slot-prepend-prototype slot values #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (yuanxu-graph-slot-remove slot values)
  (yuanxu-graph-operation-instance
   yuanxu-graph-slot-remove-prototype slot values #f #f))

;; : (-> YuanxuGraph PooGraphOperation)
(def (yuanxu-graph-node-extend node)
  (yuanxu-graph-operation-instance
   yuanxu-graph-node-extend-prototype #f #f node #f))

;; : (-> Symbol PooGraphOperation)
(def (yuanxu-graph-node-remove target)
  (yuanxu-graph-operation-instance
   yuanxu-graph-node-remove-prototype #f #f #f target))

;;; Apply dispatch is supplied by the concrete operation prototype.
;; : (-> PooGraphOperation YuanxuGraph YuanxuGraph)
(.defgeneric (yuanxu-graph-operation-apply operation node)
  slot: .apply)

;;; Public order remains node-first while semantic dispatch stays receiver-first.
;; : (-> YuanxuGraph PooGraphOperation YuanxuGraph)
(def (yuanxu-graph-apply-operation node operation)
  (yuanxu-graph-operation-apply operation node))

;;; Batch-state dispatch is likewise owned by operation prototypes.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(.defgeneric (yuanxu-graph-operation-state operation state)
  slot: .stage)

;; : (-> PooGraphOperation Boolean)
(def (yuanxu-graph-local-operation? operation)
  (.ref operation 'local?))

;; : (-> PooGraphOperation Boolean)
(def (yuanxu-graph-node-extend-operation? operation)
  (.ref operation 'node-extend?))

;; : (-> PooGraphOperation Boolean)
(def (yuanxu-graph-slot-append-operation? operation)
  (.ref operation 'slot-append?))

;; : (forall (a) (-> [a] [a] [a]))
;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-graph-slot-values/rev-onto values tail)
  (foldl cons tail values))

;;; Emit the pending slot append batch when coalescing changes families.
;; : (-> Boolean MaybeSymbol [PooModuleSlotValue] [PooGraphOperation] [PooGraphOperation])
(def (yuanxu-graph-flush-slot-append pending? slot reversed-values output)
  (if pending?
    (cons (yuanxu-graph-slot-append
           slot
           (reverse reversed-values))
          output)
    output))

;; yuanxu-graph-coalesce-slot-appends
;;   : (-> [PooGraphOperation] [PooGraphOperation])
;;   | doc m%
;;       Adjacent appends for one slot collapse before generic application.
;;       Other operation families remain opaque and retain prototype order.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-coalesce-slot-appends operations)
;;       ;; => ordered operations with adjacent same-slot appends combined
;;       ```
;;     %
(def (yuanxu-graph-coalesce-slot-appends operations)
  (let loop ((remaining operations)
             (pending? #f)
             (pending-slot #f)
             (pending-values '())
             (output '()))
    (if (null? remaining)
      (reverse
       (yuanxu-graph-flush-slot-append pending?
                                                    pending-slot
                                                    pending-values
                                                    output))
      (let (operation (car remaining))
        (if (yuanxu-graph-slot-append-operation? operation)
          (let* ((slot (yuanxu-graph-operation-slot operation))
                 (values
                  (yuanxu-graph-list-value
                   (yuanxu-graph-operation-value operation))))
            (if (and pending? (equal? pending-slot slot))
              (loop (cdr remaining)
                    #t
                    pending-slot
                    (yuanxu-graph-slot-values/rev-onto
                     values pending-values)
                    output)
              (loop (cdr remaining)
                    #t
                    slot
                    (reverse values)
                    (yuanxu-graph-flush-slot-append
                     pending? pending-slot pending-values output))))
          (loop (cdr remaining)
                #f
                #f
                '()
                (cons operation
                      (yuanxu-graph-flush-slot-append
                       pending? pending-slot pending-values output))))))))
