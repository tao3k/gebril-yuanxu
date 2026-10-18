;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Rooted containment views use the ordinary Graph nodes and edges. Node IDs
;;; are paths, so equal local names in different branches remain distinct.
;;; Payloads belong to callers. All reachability uses the shared graph walker.
(import (only-in :std/list/list find last)
        (only-in :clan/poo/object .cc)
        :core/graph/types
        :core/graph/algorithms)
(export (import: :core/graph/types)
        poo-flow-graph-rooted
        poo-flow-graph-root-id
        poo-flow-graph-root-payload
        poo-flow-graph-root-children
        poo-flow-graph-root-ref
        poo-flow-graph-root-replace
        poo-flow-graph-root-transform
        poo-flow-graph-root-snapshot)

(def (poo-flow-graph-root-id value)
  (last (poo-flow-graph-id value)))

(def (graph-root-node value)
  (find (lambda (node)
          (equal? (poo-flow-graph-node-id node) (poo-flow-graph-id value)))
        (poo-flow-graph-nodes value)))

(def (poo-flow-graph-root-payload value)
  (poo-flow-graph-node-payload (graph-root-node value)))

(def (graph-path-rebase path old-root new-root)
  (append new-root (list-tail path (length old-root))))

(def (graph-root-rebase value new-root)
  (let* ((old-root (poo-flow-graph-id value))
         (rebase (lambda (path) (graph-path-rebase path old-root new-root))))
    (poo-flow-graph
     new-root
     (map (lambda (node)
            (.cc node id: (rebase (poo-flow-graph-node-id node))))
          (poo-flow-graph-nodes value))
     (map (lambda (edge)
            (.cc edge from: (rebase (poo-flow-graph-edge-from edge))
                      to: (rebase (poo-flow-graph-edge-to edge))))
          (poo-flow-graph-edges value))
     (poo-flow-graph-metadata value))))

(def (poo-flow-graph-rooted identity payload children)
  (let* ((root (list identity))
         (branches
          (map (lambda (child)
                 (graph-root-rebase
                  child (append root (list (poo-flow-graph-root-id child)))))
               children)))
    (poo-flow-graph
     root
     (cons (poo-flow-graph-node root payload)
           (apply append (map poo-flow-graph-nodes branches)))
     (apply append
       (map (lambda (branch)
              (cons (poo-flow-graph-edge root (poo-flow-graph-id branch) 'contains)
                    (poo-flow-graph-edges branch)))
            branches)))))

(def (graph-root-view value root)
  (let* ((reachable (poo-flow-graph-reachable-ids value (list root)))
         (selected (make-hash-table)))
    (for-each (lambda (id) (hash-put! selected id #t)) reachable)
    (poo-flow-graph
     root
     (filter (lambda (node) (hash-get selected (poo-flow-graph-node-id node)))
             (poo-flow-graph-nodes value))
     (filter (lambda (edge)
               (and (hash-get selected (poo-flow-graph-edge-from edge))
                    (hash-get selected (poo-flow-graph-edge-to edge))))
             (poo-flow-graph-edges value))
     (poo-flow-graph-metadata value))))

(def (poo-flow-graph-root-children value)
  (map (lambda (id) (graph-root-view value id))
       (poo-flow-graph-outgoing-ids value (poo-flow-graph-id value))))

(def (poo-flow-graph-root-ref values identity)
  (find (lambda (value) (equal? (poo-flow-graph-root-id value) identity)) values))

(def (poo-flow-graph-root-replace value payload children)
  (let (next (poo-flow-graph-rooted (poo-flow-graph-root-id value) payload children))
    (let* ((rebased (graph-root-rebase next (poo-flow-graph-id value)))
           (root-id (poo-flow-graph-id value))
           (root-node (graph-root-node value)))
      (.cc rebased
           metadata: (poo-flow-graph-metadata value)
           nodes: (map (lambda (node)
                         (if (equal? (poo-flow-graph-node-id node) root-id)
                           (.cc root-node payload: payload)
                           node))
                       (poo-flow-graph-nodes rebased))))))

;;; A matched ancestor owns its entire subtree; do not apply again below it.
;;; This traversal is shared by graph transformations, not extension dispatch.
(def (poo-flow-graph-root-transform value identity transform)
  (if (equal? (if (list? identity)
                  (poo-flow-graph-id value)
                  (poo-flow-graph-root-id value))
              identity)
    (transform value)
    (poo-flow-graph-root-replace
     value
     (poo-flow-graph-root-payload value)
     (map (lambda (child)
            (poo-flow-graph-root-transform child identity transform))
          (poo-flow-graph-root-children value)))))

;;; Compare semantic facts, excluding POO identity and lazy slot caches.
(def (poo-flow-graph-root-snapshot value)
  (list
   (poo-flow-graph-id value)
   (map (lambda (node)
          (list (poo-flow-graph-node-id node) (poo-flow-graph-node-payload node)))
        (poo-flow-graph-nodes value))
   (poo-flow-graph-edge-pairs value)))
