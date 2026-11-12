;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public Graph mechanism: topology, pure analysis and POO operation values.

(import :tao3k/yuanxu/graph/algorithms
        :tao3k/yuanxu/graph/rooted
        :tao3k/yuanxu/graph/contribution
        :tao3k/yuanxu/graph/payload-operations
        :tao3k/yuanxu/graph/operation
        :tao3k/yuanxu/graph/apply)

(export (import: :tao3k/yuanxu/graph/algorithms)
        (import: :tao3k/yuanxu/graph/rooted)
        yuanxu-graph-operation-kind
        yuanxu-graph-contribution-kind
        yuanxu-graph-result-kind
        yuanxu-graph-slot-override
        yuanxu-graph-slot-append
        yuanxu-graph-slot-prepend
        yuanxu-graph-slot-remove
        yuanxu-graph-node-extend
        yuanxu-graph-node-remove
        yuanxu-graph-contribution
        yuanxu-graph-contribution?
        yuanxu-graph-contribution-target
        yuanxu-graph-contribution-operations
        yuanxu-graph-apply-contribution
        yuanxu-graph-apply-contributions
        yuanxu-graph-resolve
        yuanxu-graph-result
        yuanxu-graph-result?
        yuanxu-graph-result-root
        yuanxu-graph-result-changed-passes
        yuanxu-graph-result-applied?
)
