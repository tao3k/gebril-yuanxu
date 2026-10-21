;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: extension contribution coalescing and single-pass resolution.

(import (only-in :clan/poo/object
                 .o
                 .ref
                 object?)
        :yuanxu/graph/contribution
        :yuanxu/graph/payload-operations
        :yuanxu/graph/operation)

(export yuanxu-graph-apply-operations
        yuanxu-graph-local-operations?
        yuanxu-graph-reverse-onto
        yuanxu-graph-flush-coalesced
        yuanxu-graph-coalesce-local-contributions
        yuanxu-graph-apply-contribution
        yuanxu-graph-apply-contributions/coalesced
        yuanxu-graph-apply-contributions
        yuanxu-graph-resolve)

;; : (-> [PooGraphOperation] PooGraphOperationState PooGraphOperationState)
(def (yuanxu-graph-operation-state/fold operations state)
  (foldl (lambda (operation current)
           (yuanxu-graph-operation-state operation current))
         state
         operations))

;; : (-> [PooGraphOperation] Boolean)
(def (yuanxu-graph-node-extend-operations? operations)
  (andmap yuanxu-graph-node-extend-operation? operations))

;; : (-> [YuanxuGraph] [Symbol] [Symbol])
(def (yuanxu-graph-child-ids/rev children ids)
  (foldl (lambda (child current)
           (cons (yuanxu-graph-root-id child)
                 current))
         ids
         children))

;; : (-> [YuanxuGraph] HashTable HashTable Unit)
(def (yuanxu-graph-index-existing-children! children index seen)
  (for-each
   (lambda (child)
     (let (identity (yuanxu-graph-root-id child))
      (hash-put! index identity child)
      (hash-put! seen identity #t)))
   children))

;; : (-> [PooGraphOperation] HashTable HashTable [Symbol] [Symbol])
(def (yuanxu-graph-index-node-extends! operations
                                                     index
                                                     seen
                                                     new-ids)
  (foldl
   (lambda (operation ids)
     (let* ((node (yuanxu-graph-operation-node operation))
            (identity (yuanxu-graph-root-id node))
            (known? (hash-get seen identity)))
       (hash-put! index identity
                  (if known?
                    (yuanxu-graph-node-merge (hash-get index identity) node)
                    node))
       (if known?
         ids
         (begin
           (hash-put! seen identity #t)
           (cons identity ids)))))
   new-ids
   operations))

;; : (-> [Symbol] HashTable [YuanxuGraph] [YuanxuGraph])
(def (yuanxu-graph-ids->children/rev ids index children)
  (foldl (lambda (identity current)
           (cons (hash-get index identity) current))
         children
         ids))

;; yuanxu-graph-apply-node-extends
;; : (-> YuanxuGraph [PooGraphOperation] YuanxuGraph)
;; | doc m%
;;   Apply a batch of node-extend operations by indexing existing and new children.
;;   # Examples
;;   ```scheme
;;   (yuanxu-graph-apply-node-extends node operations)
;;   ;; => node with child extensions merged by identity
;;   ```
(def (yuanxu-graph-apply-node-extends node operations)
  (let* ((children (yuanxu-graph-root-children node))
         (index (make-hash-table))
         (seen (make-hash-table)))
    (yuanxu-graph-index-existing-children! children index seen)
    (let* ((base-ids
            (reverse
             (yuanxu-graph-child-ids/rev children '())))
           (new-ids
            (reverse
             (yuanxu-graph-index-node-extends!
              operations
              index
              seen
              '())))
           (merged-ids (append base-ids new-ids)))
      (yuanxu-graph-root-replace
       node
       (yuanxu-graph-root-payload node)
       (reverse
        (yuanxu-graph-ids->children/rev
         merged-ids
         index
         '()))))))

;; yuanxu-graph-apply-operations
;;   : (-> YuanxuGraph (List PooGraphOperation) YuanxuGraph)
;;   | doc m%
;;       `yuanxu-graph-apply-operations` coalesces slot append
;;       operations before applying pending node extension and slot override
;;       batches to one extension node.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-apply-operations node operations)
;;       ;; => node with coalesced local slot operations applied
;;       ```
;;     %
(def (yuanxu-graph-apply-operations node operations)
  (if (yuanxu-graph-node-extend-operations? operations)
    (yuanxu-graph-apply-node-extends node operations)
    (match (yuanxu-graph-operation-state/fold
            (yuanxu-graph-coalesce-slot-appends operations)
            [node '() '()])
      ([current pending-node-extends pending-slot-overrides]
       (yuanxu-graph-flush-pending current
                                                pending-node-extends
                                                pending-slot-overrides)))))

;;; Local batches may be coalesced only when every operation stays within the
;;; current target; graph-wide operations must force a contribution boundary.
;; : (-> [PooGraphOperation] Boolean)
(def (yuanxu-graph-local-operations? operations)
  (andmap yuanxu-graph-local-operation? operations))

;;; Reversing into an existing tail is the hot append-free path for pending
;;; operation stacks, preserving order without allocating intermediate appends.
;; : (forall (a) (-> (List a) (List a) (List a)))
;; : (-> List List List)
(def (yuanxu-graph-reverse-onto values tail)
  (foldl cons tail values))

;;; Flushing is guarded by the pending flag so empty coalescing state never
;;; creates synthetic contributions or changes target ordering.
;; yuanxu-graph-flush-coalesced
;; : (-> Boolean MaybeSymbol [PooGraphOperation] [PooGraphContribution] [PooGraphContribution])
;; | doc m%
;;   Append one pending coalesced contribution when the fold state is active.
;;   # Examples
;;   ```scheme
;;   (yuanxu-graph-flush-coalesced #t 'root operations output)
;;   ;; => output with one pending contribution
;;   ```
(def (yuanxu-graph-flush-coalesced pending? target reversed-operations output)
  (if pending?
    (cons (yuanxu-graph-contribution
           target
           (reverse reversed-operations))
          output)
    output))

;;; Contribution coalescing keeps adjacent same-target local operations in one
;;; batch and flushes as soon as the target or operation scope changes.
;; : (-> PooGraphCoalesceState PooGraphContribution PooGraphCoalesceState)
(def (yuanxu-graph-coalesce-contribution-state state contribution)
  (match state
    ([pending? pending-target pending-operations output]
     (let ((target
            (yuanxu-graph-contribution-target contribution))
           (operations
            (yuanxu-graph-contribution-operations contribution)))
       (if (yuanxu-graph-local-operations? operations)
         (if (and pending? (equal? pending-target target))
           [#t
            pending-target
            (yuanxu-graph-reverse-onto operations
                                                    pending-operations)
            output]
           [#t
            target
            (reverse operations)
            (yuanxu-graph-flush-coalesced pending?
                                                       pending-target
                                                       pending-operations
                                                       output)])
         [#f
          #f
          '()
          (cons contribution
                (yuanxu-graph-flush-coalesced
                 pending?
                 pending-target
                 pending-operations
                 output))])))))

;;; Output materialization is the only place the reversed coalescing accumulator
;;; is exposed, keeping the state tuple append-free during the fold.
;; : (-> PooGraphCoalesceState [PooGraphContribution])
(def (yuanxu-graph-coalesce-state-output state)
  (match state
    ([pending? pending-target pending-operations output]
     (reverse
      (yuanxu-graph-flush-coalesced pending?
                                                 pending-target
                                                 pending-operations
                                                 output)))))

;; yuanxu-graph-coalesce-local-contributions
;;   : (-> (List PooGraphContribution) (List PooGraphContribution))
;;   | doc m%
;;       `yuanxu-graph-coalesce-local-contributions contributions`
;;       combines adjacent local contributions for the same target so ordered
;;       point extension passes apply one compact operation batch per target.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-coalesce-local-contributions
;;        (list
;;         (yuanxu-graph-contribution
;;          'root
;;          (list (yuanxu-graph-slot-override 'mode 'strict)))
;;         (yuanxu-graph-contribution
;;          'root
;;          (list (yuanxu-graph-slot-append 'features
;;                                                      '(extra))))))
;;       ;; => ((root (slot-override slot-append)))
;;       ```
;;     %
(def (yuanxu-graph-coalesce-local-contributions/fold
      contributions
      state)
  (foldl (lambda (contribution current)
           (yuanxu-graph-coalesce-contribution-state
            current
            contribution))
         state
         contributions))

;; : (-> [PooGraphContribution] [PooGraphContribution])
(def (yuanxu-graph-coalesce-local-contributions contributions)
  (yuanxu-graph-coalesce-state-output
   (yuanxu-graph-coalesce-local-contributions/fold
    contributions
    [#f #f '() '()])))

;;; Graph owns target lookup and structural traversal. Operation prototypes
;;; apply only at the selected root; they do not define another graph walker.
(def (yuanxu-graph-apply-contribution graph-value contribution)
  (yuanxu-graph-root-transform
   graph-value
   (yuanxu-graph-contribution-target contribution)
   (lambda (target)
     (yuanxu-graph-apply-operations
      target
      (yuanxu-graph-contribution-operations contribution)))))

;;; The coalesced path assumes contribution order is already compacted, so it
;;; can fold directly over graph updates without another normalization pass.
;; : (-> YuanxuGraph [PooGraphContribution] YuanxuGraph)
(def (yuanxu-graph-apply-contributions/coalesced-loop
      current
      contributions)
  (foldl (lambda (contribution node)
           (yuanxu-graph-apply-contribution node contribution))
         current
         contributions))

;; : (-> YuanxuGraph [PooGraphContribution] YuanxuGraph)
(def (yuanxu-graph-apply-contributions/coalesced node contributions)
  (yuanxu-graph-apply-contributions/coalesced-loop node
                                                                contributions))

;; : (-> YuanxuGraph [PooGraphContribution] YuanxuGraph)
(def (yuanxu-graph-apply-contributions node contributions)
  (yuanxu-graph-apply-contributions/coalesced
   node
   (yuanxu-graph-coalesce-local-contributions contributions)))

;;; Root slot append fast path is valid only for the current root identity and
;;; pure slot append payloads, avoiding child traversal.
;; : (-> Symbol PooGraphContribution Boolean)
(def (yuanxu-graph-root-slot-append-contribution? node-identity
                                                              contribution)
  (and (equal? (yuanxu-graph-contribution-target contribution)
               node-identity)
       (andmap yuanxu-graph-slot-append-operation?
               (yuanxu-graph-contribution-operations
                contribution))))

;;; All root append contributions must satisfy the same identity guard before
;;; the batch can bypass general contribution graph traversal.
;; : (-> Symbol [PooGraphContribution] Boolean)
(def (yuanxu-graph-root-slot-append-contributions?/loop
      node-identity
      contributions)
  (cond
   ((null? contributions) #t)
   ((yuanxu-graph-root-slot-append-contribution?
     node-identity
     (car contributions))
    (yuanxu-graph-root-slot-append-contributions?/loop
     node-identity
     (cdr contributions)))
   (else #f)))

;; : (-> Symbol [PooGraphContribution] Boolean)
(def (yuanxu-graph-root-slot-append-contributions? node-identity
                                                                contributions)
  (yuanxu-graph-root-slot-append-contributions?/loop
   node-identity
   contributions))

;; yuanxu-graph-fast-slot-append-slots
;;   : (-> PooModuleSlotMap (List PooGraphContribution) Pair)
;;   | doc m%
;;       `yuanxu-graph-fast-slot-append-slots` materializes the
;;       root-only slot append fast path by indexing existing values once,
;;       collecting new additions in reverse, and preserving slot order.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-fast-slot-append-slots slots contributions)
;;       ;; => pair of updated slots and changed? flag
;;       ```
;;     %
(def (yuanxu-graph-fast-slot-append-slots slots contributions)
  (let ((base-seen (make-hash-table))
        (new-seen (make-hash-table))
        (active (make-hash-table))
        (bases (make-hash-table))
        (additions (make-hash-table))
        (value-indexes (make-hash-table)))
    (for-each
     (lambda (entry)
       (hash-put! base-seen
                  (yuanxu-graph-entry-key entry)
                  #t))
     slots)
    (def (slot-base key)
      (yuanxu-graph-list-value
       (yuanxu-graph-alist-ref/default slots key '())))
    (def (base-slot? key) (hash-get base-seen key))
    (def (new-slot-seen? key) (hash-get new-seen key))
    (def (new-slot? key)
      (and (not (base-slot? key))
           (not (new-slot-seen? key))))
    (def (remember-new-slot! key)
      (hash-put! new-seen key #t))
    (def (slot-active? key) (hash-get active key))
    (def (slot-base-list key) (hash-get bases key))
    (def (slot-additions key) (hash-get additions key))
    (def (set-slot-additions! key values)
      (hash-put! additions key values))
    (def (slot-value-index key) (hash-get value-indexes key))
    (def (append-operation-slot operation)
      (yuanxu-graph-operation-slot operation))
    (def (append-operation-value-list operation)
      (yuanxu-graph-list-value
       (yuanxu-graph-operation-value operation)))
    (def (activate-slot! key)
      (if (slot-active? key)
        #f
        (let (base (slot-base key))
          (hash-put! active key #t)
          (hash-put! bases key base)
          (hash-put! additions key '())
          (hash-put! value-indexes
                     key
                     (yuanxu-graph-value-index base)))))
    (def (append-operation-values! operation)
      (let* ((key (append-operation-slot operation))
             (values (append-operation-value-list operation))
             (operation-new-slot? (new-slot? key)))
        (activate-slot! key)
        (if operation-new-slot?
          (remember-new-slot! key))
        (let (seen (slot-value-index key))
          (let loop ((remaining values)
                     (next-additions (slot-additions key))
                     (changed? operation-new-slot?))
            (cond
             ((null? remaining)
              (set-slot-additions! key next-additions)
              changed?)
             ((hash-get seen (car remaining))
              (loop (cdr remaining) next-additions changed?))
             (else
              (hash-put! seen (car remaining) #t)
              (loop (cdr remaining)
                    (cons (car remaining) next-additions)
                    #t)))))))
    (def (materialize-slot key)
      (let ((base (slot-base-list key))
            (extra (slot-additions key)))
        (if (null? extra)
          base
          (append base (reverse extra)))))
    (def (materialize-existing-slots/rev remaining result-rev)
      (if (null? remaining)
        result-rev
        (let* ((entry (car remaining))
               (key (yuanxu-graph-entry-key entry)))
          (materialize-existing-slots/rev
           (cdr remaining)
           (cons (if (slot-active? key)
                   (yuanxu-graph-entry
                    key
                    (materialize-slot key))
                   entry)
                 result-rev)))))
    (def (materialize-new-slots/rev remaining-new-order result-rev)
      (if (null? remaining-new-order)
        result-rev
        (let (key (car remaining-new-order))
          (materialize-new-slots/rev
           (cdr remaining-new-order)
           (cons (yuanxu-graph-entry key (materialize-slot key))
                 result-rev)))))
    (def (materialize-slots new-order)
      (reverse
       (materialize-new-slots/rev
        (reverse new-order)
        (materialize-existing-slots/rev slots '()))))
    (let loop-contributions ((remaining-contributions contributions)
                             (new-order '())
                             (changed? #f))
      (if (null? remaining-contributions)
        (if (and (not changed?) (null? new-order))
          (cons slots #f)
          (cons (materialize-slots new-order) #t))
        (let loop-operations
            ((remaining-operations
              (yuanxu-graph-contribution-operations
               (car remaining-contributions)))
             (next-new-order new-order)
             (next-changed? changed?))
          (if (null? remaining-operations)
            (loop-contributions (cdr remaining-contributions)
                                next-new-order
                                next-changed?)
            (let* ((operation (car remaining-operations))
                   (key (append-operation-slot operation))
                   (operation-new-slot? (new-slot? key))
                   (operation-changed?
                    (append-operation-values! operation)))
              (loop-operations
               (cdr remaining-operations)
               (if operation-new-slot?
                 (cons key next-new-order)
                 next-new-order)
               (or next-changed? operation-changed?)))))))))

;;; This root-only shortcut converts the slot append pair into an application receipt
;;; without walking children, preserving the changed-pass receipt.
;; : (-> YuanxuGraph [PooGraphContribution] MaybePooGraphResult)
(def (yuanxu-graph-fast-root-slot-append-result base contributions)
  (let ((node-identity (yuanxu-graph-root-id base))
        (children (yuanxu-graph-root-children base)))
    (and (null? children)
         (yuanxu-graph-root-slot-append-contributions?
          node-identity
          contributions)
         (let (state
               (yuanxu-graph-fast-slot-append-slots
                (yuanxu-graph-root-payload base)
                contributions))
           (yuanxu-graph-result
            (yuanxu-graph-root-replace base
                                                    (car state)
                                                    children)
            (if (cdr state) 1 0)
            #t)))))

;; yuanxu-graph-resolve
;;   : (-> YuanxuGraph [PooGraphContribution] PooGraphResult)
;;   | doc m%
;;       Apply the ordered operation algebra exactly once. Native
;;       operation prototypes own behavior; Yuanxu does not run a shadow
;;       evaluator or local fixed-point engine.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-graph-resolve root contributions)
;;       ;; => completed application with a changed-pass receipt
;;       ```
;;     %
(def (yuanxu-graph-resolve base contributions)
  (or (yuanxu-graph-fast-root-slot-append-result base
                                                              contributions)
      (let (next (yuanxu-graph-apply-contributions
                  base
                  contributions))
        (yuanxu-graph-result
         next
         (if (equal? (yuanxu-graph-root-snapshot base)
                     (yuanxu-graph-root-snapshot next))
           0
           1)
         #t))))
