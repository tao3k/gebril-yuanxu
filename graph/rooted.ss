;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rooted containment views use the ordinary Graph nodes and edges. Node IDs
;;; are paths, so equal local names in different branches remain distinct.
;;; Payloads belong to callers. All reachability uses the shared graph walker.
(import (only-in :std/list/list find last)
        (only-in :clan/poo/object .cc)
        :yuanxu/graph/types
        :yuanxu/graph/algorithms
        (only-in :yuanxu/graph/algorithms-list-support
                 graph-adjacency-ref edge-pairs->outgoing-index walk-adjacency/indexed))
(export (import: :yuanxu/graph/types)
        yuanxu-graph-rooted
        yuanxu-graph-root-id
        yuanxu-graph-root-payload
        yuanxu-graph-root-children
        yuanxu-graph-root-ref
        yuanxu-graph-root-replace
        yuanxu-graph-root-transform
        yuanxu-graph-root-snapshot)

(def (yuanxu-graph-root-id value)
  (last (yuanxu-graph-id value)))

(def (graph-root-node value)
  (find (lambda (node)
          (equal? (yuanxu-graph-node-id node) (yuanxu-graph-id value)))
        (yuanxu-graph-nodes value)))

(def (yuanxu-graph-root-payload value)
  (yuanxu-graph-node-payload (graph-root-node value)))

(def (graph-path-rebase path old-root new-root)
  (append new-root (list-tail path (length old-root))))

(def (graph-root-rebase value new-root)
  (let* ((old-root (yuanxu-graph-id value))
         (rebase (lambda (path) (graph-path-rebase path old-root new-root))))
    (yuanxu-graph
     new-root
     (map (lambda (node)
            (.cc node id: (rebase (yuanxu-graph-node-id node))))
          (yuanxu-graph-nodes value))
     (map (lambda (edge)
            (.cc edge from: (rebase (yuanxu-graph-edge-from edge))
                      to: (rebase (yuanxu-graph-edge-to edge))))
          (yuanxu-graph-edges value))
     (yuanxu-graph-metadata value))))

;; Build at the final path once. Replacing a nested root must not first build
;; at a temporary path and then clone every fact merely to restore its path.
(def (graph-rooted-at root root-node children metadata)
  (let (branches
         (map (lambda (child)
                (graph-root-rebase
                 child (append root (list (yuanxu-graph-root-id child)))))
              children))
    (yuanxu-graph
     root
     (cons root-node (apply append (map yuanxu-graph-nodes branches)))
     (apply append
       (map (lambda (branch)
              (cons (yuanxu-graph-edge root (yuanxu-graph-id branch) 'contains)
                    (yuanxu-graph-edges branch)))
            branches))
     metadata)))

(def (yuanxu-graph-rooted identity payload children)
  (let (root (list identity))
    (graph-rooted-at root (yuanxu-graph-node root payload) children '())))

;; Index source positions once. A view retains every original fact in original
;; order, including repeated IDs; traversal order is not publication order.
(def (graph-root-position-index values identity-of)
  (let (index (make-hash-table))
    (let loop ((rest values) (position 0))
      (if (null? rest)
        index
        (let* ((value (car rest))
               (identity (identity-of value)))
          (hash-put! index identity
            (cons (cons position value) (or (hash-get index identity) '())))
          (loop (cdr rest) (+ position 1)))))))

(def (graph-root-indexed-values identities index)
  (let (rows
         (foldl (lambda (identity found)
                  (foldl cons found (or (hash-get index identity) '())))
                '() identities))
    (map cdr (list-sort (lambda (left right) (< (car left) (car right))) rows))))

(def (graph-root-view/indexed value root outgoing nodes edges)
  (let (reachable (walk-adjacency/indexed outgoing (list root)))
    ;; Every outgoing target is visited, even for cycles or shared descendants.
    ;; Edge buckets therefore select exactly the former two-ended filter.
    (yuanxu-graph root
      (graph-root-indexed-values reachable nodes)
      (graph-root-indexed-values reachable edges)
      (yuanxu-graph-metadata value))))

(def (yuanxu-graph-root-children value)
  (let* ((outgoing
           (edge-pairs->outgoing-index
            (reverse (yuanxu-graph-edge-pairs value)) (make-hash-table)))
         (children (graph-adjacency-ref outgoing (yuanxu-graph-id value))))
    (if (null? children)
      '()
      ;; These indexes are invocation-local. No graph is retained by a global
      ;; cache, and no child repeats a scan of unrelated parent facts.
      (let ((nodes (graph-root-position-index (yuanxu-graph-nodes value)
                                             yuanxu-graph-node-id))
            (edges (graph-root-position-index (yuanxu-graph-edges value)
                                             yuanxu-graph-edge-from)))
        (map (lambda (id) (graph-root-view/indexed value id outgoing nodes edges))
             children)))))

(def (yuanxu-graph-root-ref values identity)
  (find (lambda (value) (equal? (yuanxu-graph-root-id value) identity)) values))

(def (yuanxu-graph-root-replace value payload children)
  (graph-rooted-at
   (yuanxu-graph-id value)
   (.cc (graph-root-node value) payload: payload)
   children
   (yuanxu-graph-metadata value)))

;;; A matched ancestor owns its entire subtree; do not apply again below it.
;;; Unaffected branches retain their native object instead of allocating a new
;;; graph and rebasing identical paths during every ordered contribution.
(def (yuanxu-graph-root-transform value identity transform)
  (if (equal? (if (list? identity)
                  (yuanxu-graph-id value)
                  (yuanxu-graph-root-id value))
              identity)
    (transform value)
    (let* ((children (yuanxu-graph-root-children value))
           (changed? #f)
           (next
            (map (lambda (child)
                   (let (result (yuanxu-graph-root-transform child identity transform))
                     (unless (eq? child result) (set! changed? #t))
                     result))
                 children)))
      (if changed?
        (yuanxu-graph-root-replace value (yuanxu-graph-root-payload value) next)
        value))))

;;; Compare semantic facts, excluding POO identity and lazy slot caches.
(def (yuanxu-graph-root-snapshot value)
  (list
   (yuanxu-graph-id value)
   (map (lambda (node)
          (list (yuanxu-graph-node-id node) (yuanxu-graph-node-payload node)))
        (yuanxu-graph-nodes value))
   (yuanxu-graph-edge-pairs value)))
