;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public Graph mechanism: topology, pure analysis and POO operation values.

(import :core/graph/algorithms
        :core/graph/rooted
        :core/graph/contribution
        :core/graph/payload-operations
        :core/graph/operation
        :core/graph/apply)

(export (import: :core/graph/algorithms)
        (import: :core/graph/rooted)
        poo-flow-graph-operation-kind
        poo-flow-graph-contribution-kind
        poo-flow-graph-result-kind
        poo-flow-graph-slot-override
        poo-flow-graph-slot-append
        poo-flow-graph-slot-prepend
        poo-flow-graph-slot-remove
        poo-flow-graph-node-extend
        poo-flow-graph-node-remove
        poo-flow-graph-contribution
        poo-flow-graph-contribution?
        poo-flow-graph-contribution-target
        poo-flow-graph-contribution-operations
        poo-flow-graph-apply-contribution
        poo-flow-graph-apply-contributions
        poo-flow-graph-resolve
        poo-flow-graph-result
        poo-flow-graph-result?
        poo-flow-graph-result-root
        poo-flow-graph-result-changed-passes
        poo-flow-graph-result-applied?
)
