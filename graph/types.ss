;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: graph facts are POO-native control-plane values.
;;; Invariant: graph objects describe topology; they never schedule or run it.

(export +yuanxu-graph-node-prototype-kind+
        +yuanxu-graph-edge-prototype-kind+
        +yuanxu-graph-prototype-kind+
        +yuanxu-graph-analysis-prototype-kind+
        +yuanxu-graph-loop-analysis-prototype-kind+
        graph-node
        graph-edge
        graph
        graph-analysis
        graph-loop-analysis
        YuanxuGraphNodeContract
        YuanxuGraphEdgeContract
        YuanxuGraphContract
        YuanxuGraphAnalysisContract
        YuanxuGraphLoopAnalysisContract
        yuanxu-graph-node-type-contract->alist
        yuanxu-graph-edge-type-contract->alist
        yuanxu-graph-type-contract->alist
        yuanxu-graph-analysis-type-contract->alist
        yuanxu-graph-loop-analysis-type-contract->alist
        yuanxu-graph-id?
        yuanxu-graph-require
        yuanxu-graph-every?
        yuanxu-graph-node
        yuanxu-graph-node?
        yuanxu-graph-node-id
        yuanxu-graph-node-payload
        yuanxu-graph-node-metadata
        yuanxu-graph-node->alist
        yuanxu-graph-edge
        yuanxu-graph-edge?
        yuanxu-graph-edge-from
        yuanxu-graph-edge-to
        yuanxu-graph-edge-kind
        yuanxu-graph-edge-metadata
        yuanxu-graph-edge->alist
        yuanxu-graph
        yuanxu-graph?
        yuanxu-graph-id
        yuanxu-graph-nodes
        yuanxu-graph-edges
        yuanxu-graph-metadata
        yuanxu-graph->alist
        yuanxu-graph-analysis
        yuanxu-graph-analysis?
        yuanxu-graph-analysis->alist
        yuanxu-graph-loop-analysis
        yuanxu-graph-loop-analysis?
        yuanxu-graph-loop-analysis->alist)

(import :yuanxu/graph/types-core
        :yuanxu/graph/types-contracts)
