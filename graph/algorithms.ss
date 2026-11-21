;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


;;; Boundary: pure graph algorithms over composed POO graph facts.
;;; Invariant: algorithms emit analysis facts only; runtime execution is out.

(import (only-in :std/struct/queue
                 dequeue!
                 enqueue!
                 make-Queue
                 queue-empty?)
        (only-in :std/list/list filter group-same)
        (prefix-in :clan/poo/generalized-graph graph.)
        (prefix-in :clan/poo/strong-components scc.)
        (only-in :clan/poo/dependency-analysis Computation.)
        (only-in :clan/poo/object .cc)
        :tao3k/yuanxu/graph/types-core)

(export yuanxu-graph-node-ids
        yuanxu-graph-edge-pairs
        yuanxu-graph-outgoing-ids
        yuanxu-graph-incoming-ids
        yuanxu-graph-outgoing-map
        yuanxu-graph-incoming-map
        yuanxu-graph-root-ids
        yuanxu-graph-terminal-ids
        yuanxu-graph-reachable-ids
        yuanxu-graph-dependency-cone
        yuanxu-graph-cycle-path
        yuanxu-graph-acyclic?
        yuanxu-graph-topological-order
        yuanxu-graph-topological-order/acyclic
        yuanxu-graph-analysis-receipts
        yuanxu-graph-analysis-receipt
        yuanxu-graph-loop-analysis-receipt)

(import :tao3k/yuanxu/graph/algorithms-list-support)

(def (ids->adjacency-map ids index)
  (map (lambda (id)
         (cons id (graph-adjacency-ref index id)))
       ids))

(def (yuanxu-graph-outgoing-ids graph-value id)
  (graph-adjacency-ref (yuanxu-graph-outgoing-index graph-value) id))

;; : (-> YuanxuGraph Object [Object])
(def (yuanxu-graph-incoming-ids graph-value id)
  (graph-adjacency-ref (yuanxu-graph-incoming-index graph-value) id))

;; : (-> YuanxuGraph Alist)
(def (yuanxu-graph-outgoing-map graph-value)
  (ids->adjacency-map
   (yuanxu-graph-node-ids graph-value)
   (yuanxu-graph-outgoing-index graph-value)))

;; : (-> YuanxuGraph Alist)
(def (yuanxu-graph-incoming-map graph-value)
  (ids->adjacency-map
   (yuanxu-graph-node-ids graph-value)
   (yuanxu-graph-incoming-index graph-value)))

;; : (-> YuanxuGraph [Object])
(def (yuanxu-graph-root-ids graph-value)
  (let (incoming-index (yuanxu-graph-incoming-index graph-value))
    (filter
     (lambda (id)
       (null? (graph-adjacency-ref incoming-index id)))
     (yuanxu-graph-node-ids graph-value))))

;; : (-> YuanxuGraph [Object])
(def (yuanxu-graph-terminal-ids graph-value)
  (let (outgoing-index (yuanxu-graph-outgoing-index graph-value))
    (filter
     (lambda (id)
       (null? (graph-adjacency-ref outgoing-index id)))
     (yuanxu-graph-node-ids graph-value))))

;; : (-> YuanxuGraph [Object] [Object])
(def (yuanxu-graph-reachable-ids graph-value start-ids)
  (walk-adjacency/indexed
   (yuanxu-graph-outgoing-index graph-value)
   start-ids))

;; : (-> YuanxuGraph [Object] [Object])
(def (yuanxu-graph-dependency-cone graph-value target-ids)
  (walk-adjacency/indexed
   (yuanxu-graph-incoming-index graph-value)
   target-ids))

;; : (-> YuanxuGraph MaybeList)
(def (cycle-dfs/indexed outgoing-index id stack states)
  (let ((state (hash-get states id)))
    (cond
     ((eq? state 'visiting)
      (cycle-path-from id stack))
     ((eq? state 'visited)
      #f)
     (else
      (hash-put! states id 'visiting)
        (let ((cycle
               (cycle-dfs-neighbors/indexed
                outgoing-index
                (graph-adjacency-ref outgoing-index id)
                (cons id stack)
                states)))
        (hash-put! states id 'visited)
        cycle)))))

(def (cycle-dfs-neighbors/indexed outgoing-index ids stack states)
  (cond
   ((null? ids) #f)
   (else
    (or (cycle-dfs/indexed outgoing-index
                           (car ids)
                           stack
                           states)
        (cycle-dfs-neighbors/indexed outgoing-index
                                     (cdr ids)
                                     stack
                                     states)))))

(def (find-cycle-from-nodes/indexed outgoing-index ids states)
  (cond
   ((null? ids) #f)
   (else
    (or (cycle-dfs/indexed outgoing-index
                           (car ids)
                           '()
                           states)
        (find-cycle-from-nodes/indexed outgoing-index
                                       (cdr ids)
                                       states)))))

(def (yuanxu-graph-outgoing-index graph-value)
  (edge-pairs->outgoing-index (yuanxu-graph-edge-pairs graph-value)))

(def (yuanxu-graph-incoming-index graph-value)
  (edge-pairs->incoming-index (yuanxu-graph-edge-pairs graph-value)))

(def (graph-adjacency-indexes edge-pairs)
  (values (edge-pairs->outgoing-index edge-pairs)
          (edge-pairs->incoming-index edge-pairs)))

;; Keep workflow equality and declaration order while giving POO an opaque
;; symbol per vertex. Edge-only vertices participate in structural cycles.
(def (graph-strong-components/indexed node-ids edge-pairs outgoing-index)
  (def keys (make-hash-table))
  (def ids (make-hash-table-eq))
  (def order-rev '())
  (def (key-for id)
    (or (hash-get keys id)
        (let (key (gensym 'workflow-node))
          (hash-put! keys id key)
          (hash-put! ids key id)
          (set! order-rev (cons key order-rev))
          key)))
  (def order
    (begin
      (for-each key-for node-ids)
      (for-each (lambda (edge) (key-for (car edge)) (key-for (cadr edge))) edge-pairs)
      (reverse order-rev)))
  (def codes
    (filter-map
     (lambda (key)
       (let (targets (graph-adjacency-ref outgoing-index (hash-ref ids key)))
         (and (pair? targets)
              (cons key (.cc Computation. reads: (map (cut hash-ref keys <>) targets))))))
     order))
  (def owner (scc.partition-owner (scc.partition (graph.declaration order codes))))
  ;; Project declared rows, including equal IDs declared more than once.
  (group-same node-ids key: (lambda (id) (owner (hash-ref keys id)))
    table: (make-hash-table-eq)))

(def (yuanxu-graph-cycle-path graph-value)
  (find-cycle-from-nodes/indexed
   (yuanxu-graph-outgoing-index graph-value)
   (yuanxu-graph-node-ids graph-value)
   (make-hash-table)))

;; : (-> YuanxuGraph Boolean)
(def (yuanxu-graph-acyclic? graph-value)
  (not (yuanxu-graph-cycle-path graph-value)))

;; : (-> YuanxuGraph MaybeList)
(def (yuanxu-graph-topological-order graph-value)
  (yuanxu-graph-topological-order/acyclic graph-value))

;; : (-> YuanxuGraph MaybeList)
(def (yuanxu-graph-topological-order/acyclic graph-value)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (edge-pairs (yuanxu-graph-edge-pairs graph-value))
         (outgoing-index (yuanxu-graph-outgoing-index graph-value)))
    (topological-order/indexed node-ids edge-pairs outgoing-index)))

;; : (-> [Object] [Object] [Object])
(def (yuanxu-graph-analysis-start-ids roots maybe-start+target)
  (if (or (null? maybe-start+target)
          (not (car maybe-start+target)))
    roots
    (car maybe-start+target)))

;; : (-> [Object] [Object] [Object])
(def (yuanxu-graph-analysis-target-ids terminals maybe-start+target)
  (if (or (null? maybe-start+target)
          (null? (cdr maybe-start+target))
          (not (cadr maybe-start+target)))
    terminals
    (cadr maybe-start+target)))

;; : (-> YuanxuGraph MaybeList MaybeList)
(def (yuanxu-graph-analysis-topological-order*
      node-ids edge-pairs outgoing-index cycle-path)
  (if cycle-path
    #f
    (topological-order/indexed node-ids edge-pairs outgoing-index)))

;; : (-> MaybeList Alist)
(def (yuanxu-graph-analysis-diagnostics cycle-path)
  (if cycle-path
    (list (cons 'cycle-path cycle-path))
    '()))

;; : (-> YuanxuGraph [Object] [[Object Object]] HashTable HashTable List YuanxuGraphAnalysis)
(def (graph-analysis-receipt/indexed graph-value node-ids edge-pairs
                                     outgoing-index incoming-index
                                     maybe-start+target)
  (let* ((roots
              (filter
               (lambda (id)
                 (null? (graph-adjacency-ref incoming-index id)))
               node-ids))
             (terminals
              (filter
               (lambda (id)
                 (null? (graph-adjacency-ref outgoing-index id)))
               node-ids))
             (start-ids
              (yuanxu-graph-analysis-start-ids roots maybe-start+target))
             (target-ids
              (yuanxu-graph-analysis-target-ids terminals maybe-start+target))
             (cycle-path
              (find-cycle-from-nodes/indexed
               outgoing-index node-ids (make-hash-table)))
             (topological-order
              (yuanxu-graph-analysis-topological-order*
               node-ids edge-pairs outgoing-index cycle-path))
             (diagnostics
              (yuanxu-graph-analysis-diagnostics cycle-path)))
        (yuanxu-graph-analysis
         (yuanxu-graph-id graph-value)
         (length node-ids)
         (length edge-pairs)
         roots
         terminals
         (walk-adjacency/indexed outgoing-index start-ids)
         (walk-adjacency/indexed incoming-index target-ids)
         topological-order
         cycle-path
         diagnostics)))

;; : (-> YuanxuGraph YuanxuGraphAnalysis)
(def (yuanxu-graph-analysis-receipt graph-value . maybe-start+target)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (edge-pairs (yuanxu-graph-edge-pairs graph-value)))
    (let-values (((outgoing-index incoming-index)
                  (graph-adjacency-indexes edge-pairs)))
      (graph-analysis-receipt/indexed
       graph-value node-ids edge-pairs outgoing-index incoming-index
       maybe-start+target))))

;; : (-> YuanxuGraph [Object] [[Object Object]] HashTable YuanxuGraphLoopAnalysis)
(def (graph-loop-analysis-receipt/indexed graph-value node-ids edge-pairs
                                          outgoing-index)
  (let* ((components (graph-strong-components/indexed node-ids edge-pairs outgoing-index))
         (component-index (components->membership components)))
      (let* ((cyclic-components
              (select-cyclic-components components outgoing-index))
             (condensation-edges
              (graph-condensation-edges
               edge-pairs
               component-index))
             (diagnostics
              (yuanxu-graph-loop-analysis-diagnostics cyclic-components)))
        (yuanxu-graph-loop-analysis
         (yuanxu-graph-id graph-value)
         components
         cyclic-components
         condensation-edges
         diagnostics))))

;; Build the shared graph projection and adjacency indexes once when callers
;; require both the ordinary and loop-analysis receipts.
;; : (-> YuanxuGraph (Values YuanxuGraphAnalysis YuanxuGraphLoopAnalysis))
(def (yuanxu-graph-analysis-receipts graph-value . maybe-start+target)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (edge-pairs (yuanxu-graph-edge-pairs graph-value)))
    (let-values (((outgoing-index incoming-index)
                  (graph-adjacency-indexes edge-pairs)))
      (values
       (graph-analysis-receipt/indexed
        graph-value node-ids edge-pairs outgoing-index incoming-index
        maybe-start+target)
       (graph-loop-analysis-receipt/indexed
        graph-value node-ids edge-pairs outgoing-index)))))

;; : (-> YuanxuGraph YuanxuGraphLoopAnalysis)
(def (yuanxu-graph-loop-analysis-receipt graph-value)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (edge-pairs (yuanxu-graph-edge-pairs graph-value))
         (outgoing-index
          (edge-pairs->outgoing-index edge-pairs)))
    (graph-loop-analysis-receipt/indexed
     graph-value node-ids edge-pairs outgoing-index)))

(def (yuanxu-graph-loop-analysis-diagnostics cyclic-components)
  (if (null? cyclic-components)
    '()
    (list (cons 'cyclic-components cyclic-components))))

(def (index-component-members! members membership component-id)
  (for-each
   (lambda (member) (hash-put! membership member component-id))
   members))

(def (components->membership components)
  (let (membership (make-hash-table))
    (let loop ((remaining components) (component-id 0))
      (unless (null? remaining)
        (index-component-members! (car remaining) membership component-id)
        (loop (cdr remaining) (+ component-id 1))))
    membership))

(def (select-cyclic-components components outgoing-index)
  (cond
   ((null? components) '())
   ((component-cyclic? (car components) outgoing-index)
    (cons (car components)
          (select-cyclic-components (cdr components) outgoing-index)))
   (else
    (select-cyclic-components (cdr components) outgoing-index))))

(def (component-cyclic? component outgoing-index)
  (or (not (null? (cdr component)))
      (member (car component)
              (graph-adjacency-ref outgoing-index (car component)))))

(def (graph-condensation-edges edge-pairs component-index)
  (reverse
   (graph-condensation-edges/rev
    edge-pairs component-index (make-hash-table) '())))

(def (graph-condensation-edges/rev edge-pairs component-index seen edges-rev)
  (cond
   ((null? edge-pairs) edges-rev)
   (else
    (let* ((edge-pair (car edge-pairs))
           (source-component (hash-get component-index (car edge-pair)))
           (target-component (hash-get component-index (cadr edge-pair)))
           (component-edge (list source-component target-component)))
      (if (or (= source-component target-component)
              (hash-key? seen component-edge))
        (graph-condensation-edges/rev (cdr edge-pairs)
                                      component-index
                                      seen
                                      edges-rev)
        (begin
          (hash-put! seen component-edge #t)
          (graph-condensation-edges/rev (cdr edge-pairs)
                                        component-index
                                        seen
                                        (cons component-edge edges-rev))))))))

;; : (-> Object [Object] [Object])
(def (cycle-path-from id stack)
  (call/cc
   (lambda (return)
     (foldl
      (lambda (node path-tail)
        (if (equal? id node)
          (return (cons id (cycle-path-close path-tail id)))
          (cons node path-tail)))
      '()
      stack)
     (list id))))

;; : (-> [Object] Object [Object])
(def (cycle-path-close path-tail id)
  (cond
   ((null? path-tail) (list id))
   (else
    (cons (car path-tail)
          (cycle-path-close (cdr path-tail) id)))))

(def (graph-indegrees node-ids edge-pairs)
  (let (indegrees (make-hash-table))
    (for-each (lambda (id) (hash-put! indegrees id 0)) node-ids)
    (for-each
     (lambda (edge-pair)
       (let (target (cadr edge-pair))
         (when (hash-key? indegrees target)
           (hash-put! indegrees target
                      (+ 1 (hash-get indegrees target))))))
     edge-pairs)
    indegrees))

(def (topological-enqueue-targets! targets indegrees pending)
  (for-each
   (lambda (target)
     (when (hash-key? indegrees target)
       (let (next-indegree (- (hash-get indegrees target) 1))
         (hash-put! indegrees target next-indegree)
         (when (zero? next-indegree)
           (enqueue! pending target)))))
   targets))

(def (topological-order/indexed node-ids edge-pairs outgoing-index)
  (let* ((indegrees (graph-indegrees node-ids edge-pairs))
         (ready-ids
          (filter
           (lambda (id) (zero? (hash-get indegrees id)))
           node-ids))
         (node-count (length node-ids))
         (pending (make-Queue)))
    (for-each (lambda (id) (enqueue! pending id)) ready-ids)
    (let loop ((order-rev '())
               (visited-count 0))
      (if (queue-empty? pending)
        (if (= visited-count node-count)
          (reverse order-rev)
          #f)
        (let (id (dequeue! pending))
          (topological-enqueue-targets!
           (graph-adjacency-ref outgoing-index id)
           indegrees
           pending)
          (loop (cons id order-rev) (+ visited-count 1)))))))
