;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: explicit extension-node slot and child operations.

(import (only-in :clan/poo/object
                 .o
                 .ref
                 object?)
        :core/graph/contribution)

(export poo-flow-graph-slots-merge
        poo-flow-graph-node-merge
        poo-flow-graph-children-merge-one
        poo-flow-graph-children-merge
        poo-flow-graph-children-remove
        poo-flow-graph-apply-slot-list-op
        poo-flow-graph-flush-node-extends
        poo-flow-graph-flush-slot-overrides
        poo-flow-graph-flush-pending)

;; poo-flow-graph-slots-merge
;;   : (-> PooModuleSlotMap PooModuleSlotMap PooModuleSlotMap)
;;   | doc m%
;;       `poo-flow-graph-slots-merge` merges slot rows by key while
;;       preserving first declaration order and applying the last override.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-slots-merge
;;        (list (poo-flow-graph-entry 'mode 'strict))
;;        (list (poo-flow-graph-entry 'mode 'relaxed)
;;              (poo-flow-graph-entry 'features '(extra))))
;;       ;; => ((mode . relaxed) (features extra))
;;       ```
;;     %
(def (poo-flow-graph-slots-merge base extra)
  (let ((base-seen (make-hash-table))
        (override-seen (make-hash-table))
        (overrides (make-hash-table))
        (new-seen (make-hash-table))
        (replacement-used (make-hash-table)))
    ;; : (-> Any Any)
    (def (entry-slot entry)
      (poo-flow-graph-entry-key entry))
    (for-each
     (lambda (entry)
       (hash-put! base-seen
                  (entry-slot entry)
                  #t))
     base)
    ;; : (-> Any Any)
    (def (finish-entry entry)
      (let (slot (entry-slot entry))
        (if (and (hash-get override-seen slot)
                 (not (hash-get replacement-used slot)))
          (begin
            (hash-put! replacement-used slot #t)
            (poo-flow-graph-entry
             slot
             (hash-get overrides slot)))
          entry)))
    ;; : (-> Any Any)
    (def (finish-base/rev entries rows-rev)
      (if (null? entries)
        rows-rev
        (finish-base/rev (cdr entries)
                         (cons (finish-entry (car entries)) rows-rev))))
    ;; : (-> Any Any)
    (def (finish-new/rev slots rows-rev)
      (if (null? slots)
        rows-rev
        (finish-new/rev
         (cdr slots)
         (cons (poo-flow-graph-entry
                (car slots)
                (hash-get overrides (car slots)))
               rows-rev))))
    ;; : (-> Any Any)
    (def (finish new-order)
      (reverse
       (finish-new/rev
        (reverse new-order)
        (finish-base/rev base '()))))
    (let loop ((entries extra) (new-order '()))
      (if (null? entries)
        (finish new-order)
        (let* ((entry (car entries))
               (slot (entry-slot entry))
               (next-new-order
                (if (or (hash-get base-seen slot)
                        (hash-get new-seen slot))
                  new-order
                  (begin
                    (hash-put! new-seen slot #t)
                    (cons slot new-order)))))
          (hash-put! override-seen slot #t)
          (hash-put! overrides
                     slot
                     (poo-flow-graph-entry-value entry))
          (loop (cdr entries) next-new-order))))))

;; poo-flow-graph-node-merge
;;   : (-> PooFlowGraph PooFlowGraph PooFlowGraph)
;;   | doc m%
;;       `poo-flow-graph-node-merge` combines two nodes with the
;;       same identity by merging slots and children through the extension
;;       merge rules used by inheritance and contribution application.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-node-merge base-node extension-node)
;;       ;; => merged extension node
;;       ```
;;     %
(def (poo-flow-graph-node-merge base extra)
  (poo-flow-graph-root-replace
   base
   (poo-flow-graph-slots-merge
    (poo-flow-graph-root-payload base)
    (poo-flow-graph-root-payload extra))
   (poo-flow-graph-children-merge
    (poo-flow-graph-root-children base)
    (poo-flow-graph-root-children extra))))

;; poo-flow-graph-children-merge-one
;;   : (-> (List PooFlowGraph) PooFlowGraph (List PooFlowGraph))
;;   | doc m%
;;       `poo-flow-graph-children-merge-one` merges one child into
;;       an ordered child list by identity, replacing the first matching child
;;       and appending when the identity is new.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-children-merge-one children extra-child)
;;       ;; => children with extra-child merged by identity
;;       ```
;;     %
(def (poo-flow-graph-children-merge-one children extra-child)
  (cond ((null? children) (list extra-child))
        ((equal? (poo-flow-graph-root-id (car children))
                 (poo-flow-graph-root-id extra-child))
         (cons (poo-flow-graph-node-merge (car children) extra-child)
               (cdr children)))
        (else
         (cons (car children)
               (poo-flow-graph-children-merge-one (cdr children)
                                                             extra-child)))))

;; poo-flow-graph-children-merge
;;   : (-> (List PooFlowGraph) (List PooFlowGraph) (List PooFlowGraph))
;;   | doc m%
;;       `poo-flow-graph-children-merge children extra-children`
;;       merges children by node identity, preserving existing child order and
;;       appending identities that appear only in `extra-children`.
;;
;;       # Examples
;;       ```scheme
;;       (map poo-flow-graph-root-id
;;            (poo-flow-graph-children-merge
;;             (list (poo-flow-graph-rooted 'root [] []))
;;             (list (poo-flow-graph-rooted 'root '((role . main)) [])
;;                   (poo-flow-graph-rooted 'leaf [] []))))
;;       ;; => (root leaf)
;;       ```
;;     %
(def (poo-flow-graph-children-merge children extra-children)
  (if (null? extra-children)
    children
    (let ((base-seen (make-hash-table))
          (base-first (make-hash-table))
          (override-seen (make-hash-table))
          (overrides (make-hash-table))
          (new-seen (make-hash-table))
          (replacement-used (make-hash-table)))
      (for-each
       (lambda (child)
         (let (key (poo-flow-graph-root-id child))
           (if (not (hash-get base-seen key))
             (begin
               (hash-put! base-seen key #t)
               (hash-put! base-first key child))
             #f)))
       children)
      ;; : (-> Any Any)
      (def (finish-child child)
        (let (identity (poo-flow-graph-root-id child))
          (if (and (hash-get override-seen identity)
                   (not (hash-get replacement-used identity)))
            (begin
              (hash-put! replacement-used identity #t)
              (hash-get overrides identity))
            child)))
      ;; : (-> Any Any)
      (def (finish-children/rev remaining rows-rev)
        (if (null? remaining)
          rows-rev
          (finish-children/rev
           (cdr remaining)
           (cons (finish-child (car remaining)) rows-rev))))
      ;; : (-> Any Any)
      (def (finish-new/rev identities rows-rev)
        (if (null? identities)
          rows-rev
          (finish-new/rev
           (cdr identities)
           (cons (hash-get overrides (car identities)) rows-rev))))
      ;; : (-> Any Any)
      (def (finish new-order)
        (reverse
         (finish-new/rev
          (reverse new-order)
          (finish-children/rev children '()))))
      (let loop-extra ((remaining extra-children)
                       (new-order '()))
        (if (null? remaining)
          (finish new-order)
          (let* ((child (car remaining))
                 (identity (poo-flow-graph-root-id child))
                 (current (hash-get overrides identity))
                 (base-child (hash-get base-first identity))
                 (seed (if current current base-child))
                 (next-new-order
                  (if (or (hash-get base-seen identity)
                          (hash-get new-seen identity))
                    new-order
                    (begin
                      (hash-put! new-seen identity #t)
                      (cons identity new-order)))))
            (hash-put! override-seen identity #t)
            (hash-put! overrides identity
                       (if seed
                         (poo-flow-graph-node-merge seed child)
                         child))
            (loop-extra (cdr remaining) next-new-order)))))))

;; poo-flow-graph-children-remove
;;   : (-> (List PooFlowGraph) Symbol (List PooFlowGraph))
;;   | doc m%
;;       `poo-flow-graph-children-remove` removes children matching
;;       one identity while preserving the order of every remaining child.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-children-remove children 'obsolete)
;;       ;; => children without the obsolete identity
;;       ```
;;     %
(def (poo-flow-graph-children-remove children identity)
  (filter (lambda (child)
            (not (equal? (poo-flow-graph-root-id child)
                         identity)))
          children))

;; poo-flow-graph-apply-slot-list-op
;;   : (-> PooFlowGraph PooGraphOperation Boolean PooFlowGraph)
;;   | doc m%
;;       `poo-flow-graph-apply-slot-list-op` normalizes scalar and
;;       list operation values before appending or prepending distinct slot
;;       members, keeping feature rows deterministic.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-apply-slot-list-op node operation #t)
;;       ;; => node with normalized distinct list-slot values
;;       ```
;;     %
(def (poo-flow-graph-apply-slot-list-op node operation append?)
  (let* ((slot (poo-flow-graph-operation-slot operation))
         (current (poo-flow-graph-list-value
                   (poo-flow-graph-alist-ref/default
                    (poo-flow-graph-root-payload node) slot '())))
         (extra (poo-flow-graph-list-value
                 (poo-flow-graph-operation-value operation)))
         (next (if append?
                 (poo-flow-graph-append-distinct current extra)
                 (poo-flow-graph-append-distinct extra current))))
    (poo-flow-graph-root-replace
     node
     (poo-flow-graph-alist-set
      (poo-flow-graph-root-payload node) slot next)
     (poo-flow-graph-root-children node))))

;; poo-flow-graph-flush-node-extends
;;   : (-> PooFlowGraph (List PooFlowGraph) PooFlowGraph)
;;   | doc m%
;;       `poo-flow-graph-flush-node-extends` materializes reversed
;;       pending node extensions into a node through child merge semantics.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-flush-node-extends node reversed-children)
;;       ;; => node with pending child extensions merged
;;       ```
;;     %
(def (poo-flow-graph-flush-node-extends node reversed-children)
  (if (null? reversed-children)
    node
    (poo-flow-graph-root-replace
     node
     (poo-flow-graph-root-payload node)
     (poo-flow-graph-children-merge
      (poo-flow-graph-root-children node)
      (reverse reversed-children)))))

;; poo-flow-graph-flush-slot-overrides
;;   : (-> PooFlowGraph PooModuleSlotMap PooFlowGraph)
;;   | doc m%
;;       `poo-flow-graph-flush-slot-overrides` materializes reversed
;;       pending slot override rows through deterministic slot merge semantics.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-flush-slot-overrides node reversed-overrides)
;;       ;; => node with pending slot overrides merged
;;       ```
;;     %
(def (poo-flow-graph-flush-slot-overrides node reversed-overrides)
  (if (null? reversed-overrides)
    node
    (poo-flow-graph-root-replace
     node
     (poo-flow-graph-slots-merge
      (poo-flow-graph-root-payload node)
      (reverse reversed-overrides))
     (poo-flow-graph-root-children node))))

;; poo-flow-graph-flush-pending
;;   : (-> PooFlowGraph (List PooFlowGraph) PooModuleSlotMap PooFlowGraph)
;;   | doc m%
;;       `poo-flow-graph-flush-pending` commits delayed node
;;       extensions and slot overrides into the current node before an
;;       operation that cannot be coalesced is applied.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-flush-pending node children overrides)
;;       ;; => node with pending child and slot batches materialized
;;       ```
;;     %
(def (poo-flow-graph-flush-pending node reversed-children reversed-overrides)
  (poo-flow-graph-flush-node-extends
   (poo-flow-graph-flush-slot-overrides node reversed-overrides)
   reversed-children))
