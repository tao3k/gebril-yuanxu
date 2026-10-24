;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rooted containment views use the ordinary Graph nodes and edges. Node IDs
;;; are paths, so equal local names in different branches remain distinct.
;;; Payloads belong to callers. All reachability uses the shared graph walker.
(import (only-in :std/list/list find last)
        (only-in :clan/poo/object .cc)
        :yuanxu/graph/types
        :yuanxu/graph/algorithms)
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

(def (yuanxu-graph-rooted identity payload children)
  (let* ((root (list identity))
         (branches
          (map (lambda (child)
                 (graph-root-rebase
                  child (append root (list (yuanxu-graph-root-id child)))))
               children)))
    (yuanxu-graph
     root
     (cons (yuanxu-graph-node root payload)
           (apply append (map yuanxu-graph-nodes branches)))
     (apply append
       (map (lambda (branch)
              (cons (yuanxu-graph-edge root (yuanxu-graph-id branch) 'contains)
                    (yuanxu-graph-edges branch)))
            branches)))))

(def (graph-root-view value root)
  (let* ((reachable (yuanxu-graph-reachable-ids value (list root)))
         (selected (make-hash-table)))
    (for-each (lambda (id) (hash-put! selected id #t)) reachable)
    (yuanxu-graph
     root
     (filter (lambda (node) (hash-get selected (yuanxu-graph-node-id node)))
             (yuanxu-graph-nodes value))
     (filter (lambda (edge)
               (and (hash-get selected (yuanxu-graph-edge-from edge))
                    (hash-get selected (yuanxu-graph-edge-to edge))))
             (yuanxu-graph-edges value))
     (yuanxu-graph-metadata value))))

(def (yuanxu-graph-root-children value)
  (map (lambda (id) (graph-root-view value id))
       (yuanxu-graph-outgoing-ids value (yuanxu-graph-id value))))

(def (yuanxu-graph-root-ref values identity)
  (find (lambda (value) (equal? (yuanxu-graph-root-id value) identity)) values))

(def (yuanxu-graph-root-replace value payload children)
  (let (next (yuanxu-graph-rooted (yuanxu-graph-root-id value) payload children))
    (let* ((rebased (graph-root-rebase next (yuanxu-graph-id value)))
           (root-id (yuanxu-graph-id value))
           (root-node (graph-root-node value)))
      (.cc rebased
           metadata: (yuanxu-graph-metadata value)
           nodes: (map (lambda (node)
                         (if (equal? (yuanxu-graph-node-id node) root-id)
                           (.cc root-node payload: payload)
                           node))
                       (yuanxu-graph-nodes rebased))))))

;;; A matched ancestor owns its entire subtree; do not apply again below it.
;;; This traversal is shared by graph transformations, not extension dispatch.
(def (yuanxu-graph-root-transform value identity transform)
  (if (equal? (if (list? identity)
                  (yuanxu-graph-id value)
                  (yuanxu-graph-root-id value))
              identity)
    (transform value)
    (yuanxu-graph-root-replace
     value
     (yuanxu-graph-root-payload value)
     (map (lambda (child)
            (yuanxu-graph-root-transform child identity transform))
          (yuanxu-graph-root-children value)))))

;;; Compare semantic facts, excluding POO identity and lazy slot caches.
(def (yuanxu-graph-root-snapshot value)
  (list
   (yuanxu-graph-id value)
   (map (lambda (node)
          (list (yuanxu-graph-node-id node) (yuanxu-graph-node-payload node)))
        (yuanxu-graph-nodes value))
   (yuanxu-graph-edge-pairs value)))
