;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: pure graph algorithms over composed POO graph facts.
;;; Invariant: algorithms emit analysis facts only; runtime execution is out.

(import :tao3k/yuanxu/graph/types-core
        (only-in :std/list/list group-same)
        (only-in :std/struct/queue dequeue! enqueue! make-Queue queue-empty?))

(export yuanxu-graph-node-ids/rev
        yuanxu-graph-node-ids
        yuanxu-graph-edge-pairs/rev
        yuanxu-graph-edge-pairs
        ;; Internal traversal primitives shared by algorithms and rooted views.
        graph-adjacency-ref
        edge-pairs->outgoing-index
        edge-pairs->incoming-index
        walk-adjacency/indexed)

;; : (-> [YuanxuGraphNode] [Object] [Object])
(def (yuanxu-graph-node-ids/rev nodes ids-rev)
  (if (null? nodes)
    ids-rev
    (yuanxu-graph-node-ids/rev
     (cdr nodes)
     (cons (yuanxu-graph-node-id (car nodes)) ids-rev))))

;; : (-> YuanxuGraph [Object])
(def (yuanxu-graph-node-ids graph-value)
  (reverse
   (yuanxu-graph-node-ids/rev
    (yuanxu-graph-nodes graph-value)
    '())))

;; : (-> [YuanxuGraphEdge] [[Object Object]] [[Object Object]])
(def (yuanxu-graph-edge-pairs/rev edges pairs-rev)
  (if (null? edges)
    pairs-rev
    (yuanxu-graph-edge-pairs/rev
     (cdr edges)
     (cons (list (yuanxu-graph-edge-from (car edges))
                 (yuanxu-graph-edge-to (car edges)))
           pairs-rev))))

;; : (-> YuanxuGraph [[Object Object]])
(def (yuanxu-graph-edge-pairs graph-value)
  (reverse
   (yuanxu-graph-edge-pairs/rev
    (yuanxu-graph-edges graph-value)
    '())))

;; : (-> YuanxuGraph Object [Object])

;; A caller prepares one adjacency index for all views of the same graph.
(def (graph-adjacency-ref index id)
  (or (hash-get index id) '()))

;; Structural POO graphs collapse repeated edges. Workflow views expose
;; the original edge order and multiplicity, so group the authored rows.
(def (edge-pairs->adjacency-index edge-pairs endpoint neighbor)
  (def rows (make-hash-table))
  (for-each
    (lambda (bucket)
      (hash-put! rows (endpoint (car bucket)) (map neighbor bucket)))
    (group-same edge-pairs key: endpoint))
  rows)

(def (edge-pairs->outgoing-index edge-pairs)
  (edge-pairs->adjacency-index edge-pairs car cadr))

(def (edge-pairs->incoming-index edge-pairs)
  (edge-pairs->adjacency-index edge-pairs cadr car))

(def (walk-adjacency/indexed adjacency-index start-ids)
  (let ((visited (make-hash-table))
        (pending (make-Queue)))
    (for-each (lambda (id) (enqueue! pending id)) start-ids)
    (let loop ((result-rev '()))
      (if (queue-empty? pending)
        (reverse result-rev)
        (let (id (dequeue! pending))
          (if (hash-key? visited id)
            (loop result-rev)
            (begin
              (hash-put! visited id #t)
              (for-each
               (lambda (neighbor) (enqueue! pending neighbor))
               (graph-adjacency-ref adjacency-index id))
              (loop (cons id result-rev)))))))))
