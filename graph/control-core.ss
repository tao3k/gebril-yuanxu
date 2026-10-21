;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: graph control analysis implementation.
;;; Invariant: graph walks happen once per analysis receipt; runtime execution is out.

;;; Graph control analysis receipts and diagnostics.
;;; - Keep graph traversal evidence explicit before projecting bounded analysis receipts.
(import (only-in :clan/poo/object .ref)
        :yuanxu/graph/types-core
        :yuanxu/graph/algorithms
        :yuanxu/graph/control-utils)

(export yuanxu-graph-entry-ids
        yuanxu-graph-finish-ids
        yuanxu-graph-conditional-edge-pairs
        yuanxu-graph-loop-edge-pairs
        yuanxu-graph-undeclared-edge-pairs
        yuanxu-graph-unreachable-ids
        yuanxu-graph-dead-end-ids
        yuanxu-graph-finish-reachable-ids
        yuanxu-graph-branch-targets-declared?
        yuanxu-graph-finish-total?
        yuanxu-graph-control-diagnostics
        yuanxu-graph-control-analysis-receipt)

;; : (-> YuanxuGraph [Object])
(def (yuanxu-graph-entry-ids graph-value)
  (graph-entry-ids graph-value
                   (yuanxu-graph-root-ids graph-value)))

;; : (-> YuanxuGraph [Object])
(def (yuanxu-graph-finish-ids graph-value)
  (graph-finish-ids graph-value
                    (yuanxu-graph-terminal-ids graph-value)))

;; : (-> YuanxuGraph [[Object Object]])
(def (yuanxu-graph-conditional-edge-pairs graph-value)
  (edge-pairs-by-kinds graph-value +yuanxu-graph-conditional-edge-kinds+))

;; : (-> YuanxuGraph [[Object Object]])
(def (yuanxu-graph-loop-edge-pairs graph-value)
  (edge-pairs-by-kinds graph-value +yuanxu-graph-loop-edge-kinds+))

;; : (-> YuanxuGraph [[Object Object]])
(def (yuanxu-graph-undeclared-edge-pairs graph-value)
  (reverse
   (undeclared-edge-pairs/rev
    (yuanxu-graph-edges graph-value)
    (yuanxu-graph-node-ids graph-value)
    '())))

;; : (-> YuanxuGraph [Object] [Object])
(def (yuanxu-graph-unreachable-ids graph-value . maybe-start)
  (let* ((start-ids (if (null? maybe-start)
                      (yuanxu-graph-entry-ids graph-value)
                      (car maybe-start)))
         (reachable-ids (yuanxu-graph-reachable-ids graph-value
                                                       start-ids)))
    (remove-ids reachable-ids
                (yuanxu-graph-node-ids graph-value))))

;; : (-> YuanxuGraph [Object] [Object] [Object])
(def (yuanxu-graph-dead-end-ids graph-value . maybe-entry+finish)
  (let* ((entry-ids (if (null? maybe-entry+finish)
                      (yuanxu-graph-entry-ids graph-value)
                      (car maybe-entry+finish)))
         (finish-ids (if (or (null? maybe-entry+finish)
                             (null? (cdr maybe-entry+finish)))
                       (yuanxu-graph-finish-ids graph-value)
                       (cadr maybe-entry+finish)))
         (reachable-ids (yuanxu-graph-reachable-ids graph-value
                                                       entry-ids)))
    (graph-dead-end-ids graph-value reachable-ids finish-ids)))

;; : (-> YuanxuGraph [Object] [Object])
(def (yuanxu-graph-finish-reachable-ids graph-value . maybe-finish)
  (let* ((finish-ids (if (null? maybe-finish)
                       (yuanxu-graph-finish-ids graph-value)
                       (car maybe-finish)))
         (dependency-cone (yuanxu-graph-dependency-cone graph-value
                                                          finish-ids)))
    (intersection-ids (yuanxu-graph-node-ids graph-value)
                      dependency-cone)))

;; : (-> YuanxuGraph Boolean)
(def (yuanxu-graph-branch-targets-declared? graph-value)
  (ids-subset? (edge-targets-by-kinds graph-value
                                      +yuanxu-graph-conditional-edge-kinds+)
               (yuanxu-graph-node-ids graph-value)))

;; : (-> YuanxuGraph [Object] [Object] Boolean)
(def (yuanxu-graph-finish-total? graph-value . maybe-entry+finish)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (entry-ids (if (null? maybe-entry+finish)
                      (yuanxu-graph-entry-ids graph-value)
                      (car maybe-entry+finish)))
         (finish-ids (if (or (null? maybe-entry+finish)
                             (null? (cdr maybe-entry+finish)))
                       (yuanxu-graph-finish-ids graph-value)
                       (cadr maybe-entry+finish)))
         (reachable-ids (yuanxu-graph-reachable-ids graph-value
                                                       entry-ids))
         (finish-reachable-ids (yuanxu-graph-finish-reachable-ids
                                graph-value
                                finish-ids))
         (undeclared-edge-pairs
          (yuanxu-graph-undeclared-edge-pairs graph-value))
         (dead-end-ids
          (graph-dead-end-ids graph-value reachable-ids finish-ids)))
    (control-finish-total? node-ids
                           entry-ids
                           finish-ids
                           reachable-ids
                           finish-reachable-ids
                           undeclared-edge-pairs
                           dead-end-ids)))

;; : (-> YuanxuGraph [Object] [Object] Alist)
(def (yuanxu-graph-control-diagnostics graph-value . maybe-entry+finish)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (entry-ids (if (null? maybe-entry+finish)
                      (yuanxu-graph-entry-ids graph-value)
                      (car maybe-entry+finish)))
         (finish-ids (if (or (null? maybe-entry+finish)
                             (null? (cdr maybe-entry+finish)))
                       (yuanxu-graph-finish-ids graph-value)
                       (cadr maybe-entry+finish)))
         (reachable-ids (yuanxu-graph-reachable-ids graph-value
                                                       entry-ids))
         (dependency-cone (yuanxu-graph-dependency-cone graph-value
                                                          finish-ids))
         (finish-reachable-ids (intersection-ids node-ids dependency-cone))
         (undeclared-edge-pairs
          (yuanxu-graph-undeclared-edge-pairs graph-value))
         (branch-target-ids
          (edge-targets-by-kinds graph-value
                                 +yuanxu-graph-conditional-edge-kinds+))
         (unreachable-ids (remove-ids reachable-ids node-ids))
         (dead-end-ids (graph-dead-end-ids graph-value
                                           reachable-ids
                                           finish-ids))
         (finish-unreachable-ids
          (remove-ids finish-reachable-ids reachable-ids))
         (cycle-path (yuanxu-graph-cycle-path graph-value))
         (loop-edge-pairs (yuanxu-graph-loop-edge-pairs graph-value))
         (unexpected-cycle-path
          (if (and cycle-path (null? loop-edge-pairs))
            cycle-path
            #f)))
    (control-diagnostic-rows node-ids
                             entry-ids
                             finish-ids
                             undeclared-edge-pairs
                             branch-target-ids
                             unreachable-ids
                             dead-end-ids
                             finish-unreachable-ids
                             unexpected-cycle-path)))

;;; Boundary: optional caller-provided entry ids are normalized before the receipt is built.
;; : (-> YuanxuGraph GraphRootIds MaybeEntryFinish GraphEntryIds)
(def (yuanxu-graph-control-entry-ids graph-value root-ids maybe-entry+finish)
  (if (null? maybe-entry+finish)
    (graph-entry-ids graph-value root-ids)
    (car maybe-entry+finish)))

;;; Boundary: optional caller-provided finish ids share the same rest-argument protocol as entry ids.
;; : (-> YuanxuGraph GraphTerminalIds MaybeEntryFinish GraphFinishIds)
(def (yuanxu-graph-control-finish-ids graph-value
                                       terminal-ids
                                       maybe-entry+finish)
  (if (or (null? maybe-entry+finish)
          (null? (cdr maybe-entry+finish)))
    (graph-finish-ids graph-value terminal-ids)
    (cadr maybe-entry+finish)))

;;; Invariant: cyclic graphs do not expose a topological order in the analysis receipt.
;; : (-> YuanxuGraph CyclePathMaybe TopologicalOrderMaybe)
(def (yuanxu-graph-control-topological-order graph-value cycle-path)
  (if cycle-path
    #f
    (yuanxu-graph-topological-order/acyclic graph-value)))

;;; Boundary: cycle diagnostics are unexpected only when no explicit loop edge explains the cycle.
;; : (-> CyclePathMaybe LoopEdgePairs UnexpectedCyclePathMaybe)
(def (yuanxu-graph-control-unexpected-cycle-path cycle-path loop-edge-pairs)
  (if (and cycle-path (null? loop-edge-pairs))
    cycle-path
    #f))

;;; Boundary: this receipt projects graph traversal facts without executing any runtime work.
;; : (-> YuanxuGraph [Object] [Object] YuanxuGraphAnalysis)
(def (yuanxu-graph-control-analysis-receipt graph-value
                                             . maybe-entry+finish)
  (let* ((node-ids (yuanxu-graph-node-ids graph-value))
         (requested-entry-ids
          (if (null? maybe-entry+finish)
            (graph-entry-ids graph-value #f)
            (car maybe-entry+finish)))
         (requested-finish-ids
          (if (or (null? maybe-entry+finish)
                  (null? (cdr maybe-entry+finish)))
            (graph-finish-ids graph-value #f)
            (cadr maybe-entry+finish)))
         (base-analysis
          (yuanxu-graph-analysis-receipt graph-value
                                           requested-entry-ids
                                           requested-finish-ids))
         (root-ids (.ref base-analysis 'root-ids))
         (terminal-ids (.ref base-analysis 'terminal-ids))
         (entry-ids (or requested-entry-ids root-ids))
         (finish-ids (or requested-finish-ids terminal-ids))
         (cycle-path (.ref base-analysis 'cycle-path))
         (topological-order (.ref base-analysis 'topological-order))
         (reachable-ids (.ref base-analysis 'reachable-ids))
         (dependency-cone (.ref base-analysis 'dependency-cone))
         (conditional-edge-pairs
          (edge-pairs-by-kinds graph-value
                               +yuanxu-graph-conditional-edge-kinds+))
         (loop-edge-pairs
          (edge-pairs-by-kinds graph-value
                               +yuanxu-graph-loop-edge-kinds+))
         (undeclared-edge-pairs
          (reverse
           (undeclared-edge-pairs/rev
            (yuanxu-graph-edges graph-value)
            node-ids
            '())))
         (unreachable-ids (remove-ids reachable-ids node-ids))
         (dead-end-ids (graph-dead-end-ids graph-value
                                           reachable-ids
                                           finish-ids))
         (finish-reachable-ids (intersection-ids node-ids dependency-cone))
         (branch-target-ids
          (edge-targets-by-kinds graph-value
                                 +yuanxu-graph-conditional-edge-kinds+))
         (branch-targets-declared?
          (ids-subset? branch-target-ids node-ids))
         (finish-unreachable-ids
          (remove-ids finish-reachable-ids reachable-ids))
         (unexpected-cycle-path
          (yuanxu-graph-control-unexpected-cycle-path cycle-path
                                                        loop-edge-pairs))
         (finish-total?
          (control-finish-total? node-ids
                                 entry-ids
                                 finish-ids
                                 reachable-ids
                                 finish-reachable-ids
                                 undeclared-edge-pairs
                                 dead-end-ids))
         (diagnostics
          (control-diagnostic-rows node-ids
                                   entry-ids
                                   finish-ids
                                   undeclared-edge-pairs
                                   branch-target-ids
                                   unreachable-ids
                                   dead-end-ids
                                   finish-unreachable-ids
                                   unexpected-cycle-path))
         (metadata
          (list
           (control-row 'entry-ids entry-ids)
           (control-row 'finish-ids finish-ids)
           (control-row 'conditional-edge-pairs conditional-edge-pairs)
           (control-row 'loop-edge-pairs loop-edge-pairs)
           (control-row 'undeclared-edge-pairs undeclared-edge-pairs)
           (control-row 'unreachable-ids unreachable-ids)
           (control-row 'dead-end-ids dead-end-ids)
           (control-row 'finish-reachable-ids finish-reachable-ids)
           (control-row 'branch-targets-declared? branch-targets-declared?)
           (control-row 'finish-total? finish-total?))))
    (yuanxu-graph-analysis
     (yuanxu-graph-id graph-value)
     (length node-ids)
     (length (yuanxu-graph-edges graph-value))
     root-ids
     terminal-ids
     reachable-ids
     dependency-cone
     topological-order
     cycle-path
     diagnostics
     metadata)))
