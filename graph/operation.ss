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
        :core/graph/contribution
        :core/graph/payload-operations)

(export poo-flow-graph-operation-prototype
        poo-flow-graph-slot-override-prototype
        poo-flow-graph-slot-append-prototype
        poo-flow-graph-slot-prepend-prototype
        poo-flow-graph-slot-remove-prototype
        poo-flow-graph-node-extend-prototype
        poo-flow-graph-node-remove-prototype
        poo-flow-graph-slot-override
        poo-flow-graph-slot-append
        poo-flow-graph-slot-prepend
        poo-flow-graph-slot-remove
        poo-flow-graph-node-extend
        poo-flow-graph-node-remove
        poo-flow-graph-apply-operation
        poo-flow-graph-operation-state
        poo-flow-graph-local-operation?
        poo-flow-graph-node-extend-operation?
        poo-flow-graph-slot-append-operation?
        poo-flow-graph-flush-slot-append
        poo-flow-graph-coalesce-slot-appends)

;;; Ordinary operation application flushes pending batches before invoking the
;;; receiver-owned method. Specialized prototypes replace only this stage slot.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (poo-flow-graph-stage-operation operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [(poo-flow-graph-operation-apply
       operation
       (poo-flow-graph-flush-pending current
                                                pending-node-extends
                                                pending-slot-overrides))
      '()
      '()])))

;;; Node extension batches preserve encounter order until the merge boundary.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (poo-flow-graph-stage-node-extend operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [current
      (cons (poo-flow-graph-operation-node operation)
            pending-node-extends)
      pending-slot-overrides])))

;;; Slot overrides batch as key/value rows and use the common deterministic
;;; slot merge only when an operation family requires a flush.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(def (poo-flow-graph-stage-slot-override operation state)
  (match state
    ([current pending-node-extends pending-slot-overrides]
     [current
      pending-node-extends
      (cons (cons (poo-flow-graph-operation-slot operation)
                  (poo-flow-graph-operation-value operation))
            pending-slot-overrides)])))

;;; The base prototype supplies total identity behavior and common semantic
;;; facets. Concrete operation prototypes refine `.apply` and, when batchable,
;;; `.stage`; adding a family therefore does not extend a central action switch.
(def poo-flow-graph-operation-prototype
  (.o (:: self)
      kind: poo-flow-graph-operation-kind
      action: 'identity
      local?: #f
      node-extend?: #f
      slot-append?: #f
      (.apply (lambda (node) node))
      (.stage
       (lambda (state)
         (poo-flow-graph-stage-operation self state)))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-slot-override-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'slot-override
      local?: #t
      (.apply
       (lambda (node)
         (poo-flow-graph-root-replace
          node
          (poo-flow-graph-alist-set
           (poo-flow-graph-root-payload node)
           (poo-flow-graph-operation-slot self)
           (poo-flow-graph-operation-value self))
          (poo-flow-graph-root-children node))))
      (.stage
       (lambda (state)
         (poo-flow-graph-stage-slot-override self state)))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-slot-append-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'slot-append
      local?: #t
      slot-append?: #t
      (.apply
       (lambda (node)
         (poo-flow-graph-apply-slot-list-op node self #t)))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-slot-prepend-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'slot-prepend
      local?: #t
      (.apply
       (lambda (node)
         (poo-flow-graph-apply-slot-list-op node self #f)))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-slot-remove-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'slot-remove
      local?: #t
      (.apply
       (lambda (node)
         (let* ((slot (poo-flow-graph-operation-slot self))
                (current
                 (poo-flow-graph-list-value
                  (poo-flow-graph-alist-ref/default
                   (poo-flow-graph-root-payload node) slot '())))
                (removed
                 (poo-flow-graph-list-value
                  (poo-flow-graph-operation-value self))))
           (poo-flow-graph-root-replace
            node
            (poo-flow-graph-alist-set
             (poo-flow-graph-root-payload node)
             slot
             (poo-flow-graph-remove-elements current removed))
            (poo-flow-graph-root-children node)))))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-node-extend-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'node-extend
      node-extend?: #t
      (.apply
       (lambda (node)
         (poo-flow-graph-root-replace
          node
          (poo-flow-graph-root-payload node)
          (poo-flow-graph-children-merge-one
           (poo-flow-graph-root-children node)
           (poo-flow-graph-operation-node self)))))
      (.stage
       (lambda (state)
         (poo-flow-graph-stage-node-extend self state)))))

;; : PooGraphOperationPrototype
(def poo-flow-graph-node-remove-prototype
  (.o (:: self poo-flow-graph-operation-prototype)
      action: 'node-remove
      (.apply
       (lambda (node)
         (poo-flow-graph-root-replace
          node
          (poo-flow-graph-root-payload node)
          (poo-flow-graph-children-remove
           (poo-flow-graph-root-children node)
           (poo-flow-graph-operation-target self)))))))

;;; Dynamic payloads are constant defaults on a static operation prototype.
;;; This preserves inspectable slots without rebuilding method closures per row.
;; : (-> PooGraphOperationPrototype MaybeSymbol PooModuleSlotValue MaybePooFlowGraph MaybeSymbol PooGraphOperation)
(def (poo-flow-graph-operation-instance prototype slot value node target)
  (.mix prototype
    defaults: (list (cons 'slot slot)
                    (cons 'value value)
                    (cons 'node node)
                    (cons 'target target))))

;; : (-> Symbol PooModuleSlotValue PooGraphOperation)
(def (poo-flow-graph-slot-override slot value)
  (poo-flow-graph-operation-instance
   poo-flow-graph-slot-override-prototype slot value #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (poo-flow-graph-slot-append slot values)
  (poo-flow-graph-operation-instance
   poo-flow-graph-slot-append-prototype slot values #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (poo-flow-graph-slot-prepend slot values)
  (poo-flow-graph-operation-instance
   poo-flow-graph-slot-prepend-prototype slot values #f #f))

;; : (-> Symbol [PooModuleSlotValue] PooGraphOperation)
(def (poo-flow-graph-slot-remove slot values)
  (poo-flow-graph-operation-instance
   poo-flow-graph-slot-remove-prototype slot values #f #f))

;; : (-> PooFlowGraph PooGraphOperation)
(def (poo-flow-graph-node-extend node)
  (poo-flow-graph-operation-instance
   poo-flow-graph-node-extend-prototype #f #f node #f))

;; : (-> Symbol PooGraphOperation)
(def (poo-flow-graph-node-remove target)
  (poo-flow-graph-operation-instance
   poo-flow-graph-node-remove-prototype #f #f #f target))

;;; Apply dispatch is supplied by the concrete operation prototype.
;; : (-> PooGraphOperation PooFlowGraph PooFlowGraph)
(.defgeneric (poo-flow-graph-operation-apply operation node)
  slot: .apply)

;;; Public order remains node-first while semantic dispatch stays receiver-first.
;; : (-> PooFlowGraph PooGraphOperation PooFlowGraph)
(def (poo-flow-graph-apply-operation node operation)
  (poo-flow-graph-operation-apply operation node))

;;; Batch-state dispatch is likewise owned by operation prototypes.
;; : (-> PooGraphOperation PooGraphOperationState PooGraphOperationState)
(.defgeneric (poo-flow-graph-operation-state operation state)
  slot: .stage)

;; : (-> PooGraphOperation Boolean)
(def (poo-flow-graph-local-operation? operation)
  (.ref operation 'local?))

;; : (-> PooGraphOperation Boolean)
(def (poo-flow-graph-node-extend-operation? operation)
  (.ref operation 'node-extend?))

;; : (-> PooGraphOperation Boolean)
(def (poo-flow-graph-slot-append-operation? operation)
  (.ref operation 'slot-append?))

;; : (forall (a) (-> [a] [a] [a]))
;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (poo-flow-graph-slot-values/rev-onto values tail)
  (foldl cons tail values))

;;; Emit the pending slot append batch when coalescing changes families.
;; : (-> Boolean MaybeSymbol [PooModuleSlotValue] [PooGraphOperation] [PooGraphOperation])
(def (poo-flow-graph-flush-slot-append pending? slot reversed-values output)
  (if pending?
    (cons (poo-flow-graph-slot-append
           slot
           (reverse reversed-values))
          output)
    output))

;; poo-flow-graph-coalesce-slot-appends
;;   : (-> [PooGraphOperation] [PooGraphOperation])
;;   | doc m%
;;       Adjacent appends for one slot collapse before generic application.
;;       Other operation families remain opaque and retain prototype order.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-coalesce-slot-appends operations)
;;       ;; => ordered operations with adjacent same-slot appends combined
;;       ```
;;     %
(def (poo-flow-graph-coalesce-slot-appends operations)
  (let loop ((remaining operations)
             (pending? #f)
             (pending-slot #f)
             (pending-values '())
             (output '()))
    (if (null? remaining)
      (reverse
       (poo-flow-graph-flush-slot-append pending?
                                                    pending-slot
                                                    pending-values
                                                    output))
      (let (operation (car remaining))
        (if (poo-flow-graph-slot-append-operation? operation)
          (let* ((slot (poo-flow-graph-operation-slot operation))
                 (values
                  (poo-flow-graph-list-value
                   (poo-flow-graph-operation-value operation))))
            (if (and pending? (equal? pending-slot slot))
              (loop (cdr remaining)
                    #t
                    pending-slot
                    (poo-flow-graph-slot-values/rev-onto
                     values pending-values)
                    output)
              (loop (cdr remaining)
                    #t
                    slot
                    (reverse values)
                    (poo-flow-graph-flush-slot-append
                     pending? pending-slot pending-values output))))
          (loop (cdr remaining)
                #f
                #f
                '()
                (cons operation
                      (poo-flow-graph-flush-slot-append
                       pending? pending-slot pending-values output))))))))
