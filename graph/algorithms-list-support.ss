;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: pure graph algorithms over composed POO graph facts.
;;; Invariant: algorithms emit analysis facts only; runtime execution is out.

(import :yuanxu/graph/types-core)

(export yuanxu-graph-node-ids/rev
        yuanxu-graph-node-ids
        yuanxu-graph-edge-pairs/rev
        yuanxu-graph-edge-pairs)

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
