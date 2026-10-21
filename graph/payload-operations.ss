;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: explicit extension-node slot and child operations.

(import (only-in :clan/poo/object
                 .o
                 .ref
                 object?)
        :yuanxu/graph/contribution)

(export yuanxu-graph-slots-merge
        yuanxu-graph-node-merge
        yuanxu-graph-children-merge-one
        yuanxu-graph-children-merge
        yuanxu-graph-children-remove
        yuanxu-graph-apply-slot-list-op
        yuanxu-graph-flush-node-extends
        yuanxu-graph-flush-slot-overrides
        yuanxu-graph-flush-pending)

;; yuanxu-graph-slots-merge
;;   : (-> PooModuleSlotMap PooModuleSlotMap PooModuleSlotMap)
;;   | doc m%
;;       `yuanxu-graph-slots-merge` merges slot rows by key while
;;       preserving first declaration order and applying the last override.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-slots-merge
;;        (list (yuanxu-graph-entry 'mode 'strict))
;;        (list (yuanxu-graph-entry 'mode 'relaxed)
;;              (yuanxu-graph-entry 'features '(extra))))
;;       ;; => ((mode . relaxed) (features extra))
;;       ```
;;     %
(def (yuanxu-graph-slots-merge base extra)
  (let ((base-seen (make-hash-table))
        (override-seen (make-hash-table))
        (overrides (make-hash-table))
        (new-seen (make-hash-table))
        (replacement-used (make-hash-table)))
    ;; : (-> Any Any)
    (def (entry-slot entry)
      (yuanxu-graph-entry-key entry))
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
            (yuanxu-graph-entry
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
         (cons (yuanxu-graph-entry
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
                     (yuanxu-graph-entry-value entry))
          (loop (cdr entries) next-new-order))))))

;; yuanxu-graph-node-merge
;;   : (-> YuanxuGraph YuanxuGraph YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-node-merge` combines two nodes with the
;;       same identity by merging slots and children through the extension
;;       merge rules used by inheritance and contribution application.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-node-merge base-node extension-node)
;;       ;; => merged extension node
;;       ```
;;     %
(def (yuanxu-graph-node-merge base extra)
  (yuanxu-graph-root-replace
   base
   (yuanxu-graph-slots-merge
    (yuanxu-graph-root-payload base)
    (yuanxu-graph-root-payload extra))
   (yuanxu-graph-children-merge
    (yuanxu-graph-root-children base)
    (yuanxu-graph-root-children extra))))

;; yuanxu-graph-children-merge-one
;;   : (-> (List YuanxuGraph) YuanxuGraph (List YuanxuGraph))
;;   | doc m%
;;       `yuanxu-graph-children-merge-one` merges one child into
;;       an ordered child list by identity, replacing the first matching child
;;       and appending when the identity is new.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-children-merge-one children extra-child)
;;       ;; => children with extra-child merged by identity
;;       ```
;;     %
(def (yuanxu-graph-children-merge-one children extra-child)
  (cond ((null? children) (list extra-child))
        ((equal? (yuanxu-graph-root-id (car children))
                 (yuanxu-graph-root-id extra-child))
         (cons (yuanxu-graph-node-merge (car children) extra-child)
               (cdr children)))
        (else
         (cons (car children)
               (yuanxu-graph-children-merge-one (cdr children)
                                                             extra-child)))))

;; yuanxu-graph-children-merge
;;   : (-> (List YuanxuGraph) (List YuanxuGraph) (List YuanxuGraph))
;;   | doc m%
;;       `yuanxu-graph-children-merge children extra-children`
;;       merges children by node identity, preserving existing child order and
;;       appending identities that appear only in `extra-children`.
;;
;;       # Examples
;;       ```scheme
;;       (map yuanxu-graph-root-id
;;            (yuanxu-graph-children-merge
;;             (list (yuanxu-graph-rooted 'root [] []))
;;             (list (yuanxu-graph-rooted 'root '((role . main)) [])
;;                   (yuanxu-graph-rooted 'leaf [] []))))
;;       ;; => (root leaf)
;;       ```
;;     %
(def (yuanxu-graph-children-merge children extra-children)
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
         (let (key (yuanxu-graph-root-id child))
           (if (not (hash-get base-seen key))
             (begin
               (hash-put! base-seen key #t)
               (hash-put! base-first key child))
             #f)))
       children)
      ;; : (-> Any Any)
      (def (finish-child child)
        (let (identity (yuanxu-graph-root-id child))
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
                 (identity (yuanxu-graph-root-id child))
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
                         (yuanxu-graph-node-merge seed child)
                         child))
            (loop-extra (cdr remaining) next-new-order)))))))

;; yuanxu-graph-children-remove
;;   : (-> (List YuanxuGraph) Symbol (List YuanxuGraph))
;;   | doc m%
;;       `yuanxu-graph-children-remove` removes children matching
;;       one identity while preserving the order of every remaining child.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-children-remove children 'obsolete)
;;       ;; => children without the obsolete identity
;;       ```
;;     %
(def (yuanxu-graph-children-remove children identity)
  (filter (lambda (child)
            (not (equal? (yuanxu-graph-root-id child)
                         identity)))
          children))

;; yuanxu-graph-apply-slot-list-op
;;   : (-> YuanxuGraph PooGraphOperation Boolean YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-apply-slot-list-op` normalizes scalar and
;;       list operation values before appending or prepending distinct slot
;;       members, keeping feature rows deterministic.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-apply-slot-list-op node operation #t)
;;       ;; => node with normalized distinct list-slot values
;;       ```
;;     %
(def (yuanxu-graph-apply-slot-list-op node operation append?)
  (let* ((slot (yuanxu-graph-operation-slot operation))
         (current (yuanxu-graph-list-value
                   (yuanxu-graph-alist-ref/default
                    (yuanxu-graph-root-payload node) slot '())))
         (extra (yuanxu-graph-list-value
                 (yuanxu-graph-operation-value operation)))
         (next (if append?
                 (yuanxu-graph-append-distinct current extra)
                 (yuanxu-graph-append-distinct extra current))))
    (yuanxu-graph-root-replace
     node
     (yuanxu-graph-alist-set
      (yuanxu-graph-root-payload node) slot next)
     (yuanxu-graph-root-children node))))

;; yuanxu-graph-flush-node-extends
;;   : (-> YuanxuGraph (List YuanxuGraph) YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-flush-node-extends` materializes reversed
;;       pending node extensions into a node through child merge semantics.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-flush-node-extends node reversed-children)
;;       ;; => node with pending child extensions merged
;;       ```
;;     %
(def (yuanxu-graph-flush-node-extends node reversed-children)
  (if (null? reversed-children)
    node
    (yuanxu-graph-root-replace
     node
     (yuanxu-graph-root-payload node)
     (yuanxu-graph-children-merge
      (yuanxu-graph-root-children node)
      (reverse reversed-children)))))

;; yuanxu-graph-flush-slot-overrides
;;   : (-> YuanxuGraph PooModuleSlotMap YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-flush-slot-overrides` materializes reversed
;;       pending slot override rows through deterministic slot merge semantics.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-flush-slot-overrides node reversed-overrides)
;;       ;; => node with pending slot overrides merged
;;       ```
;;     %
(def (yuanxu-graph-flush-slot-overrides node reversed-overrides)
  (if (null? reversed-overrides)
    node
    (yuanxu-graph-root-replace
     node
     (yuanxu-graph-slots-merge
      (yuanxu-graph-root-payload node)
      (reverse reversed-overrides))
     (yuanxu-graph-root-children node))))

;; yuanxu-graph-flush-pending
;;   : (-> YuanxuGraph (List YuanxuGraph) PooModuleSlotMap YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-flush-pending` commits delayed node
;;       extensions and slot overrides into the current node before an
;;       operation that cannot be coalesced is applied.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-flush-pending node children overrides)
;;       ;; => node with pending child and slot batches materialized
;;       ```
;;     %
(def (yuanxu-graph-flush-pending node reversed-children reversed-overrides)
  (yuanxu-graph-flush-node-extends
   (yuanxu-graph-flush-slot-overrides node reversed-overrides)
   reversed-children))
