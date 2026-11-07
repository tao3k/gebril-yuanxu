;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: public graph control analysis facade.
;;; Invariant: keep the stable import path light; implementation lives in control-core.

(import :yuanxu/graph/control-core)

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
