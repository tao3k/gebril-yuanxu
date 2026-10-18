;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: public API re-exports the control-plane modules.
;;; Invariant: implementation logic stays in the leaf owners below.

(import :core/modules/funflow/control-plane/roles
        :core/modules/funflow/control-plane/failure
        :core/modules/funflow/control-plane/receipt
        :core/modules/funflow/control-plane/task
        :core/modules/funflow/control-plane/flow-strand
        :core/modules/funflow/control-plane/flow
        :core/modules/funflow/control-plane/flow-syntax
        :core/modules/funflow/control-plane/graph
        :core/modules/funflow/control-plane/strategy
        :core/modules/funflow/control-plane/policy
        :core/modules/funflow/control-plane/runtime-protocol
        :core/modules/funflow/control-plane/runtime-command-invocation
        :core/modules/funflow/control-plane/runtime-command-descriptor
        :core/modules/funflow/control-plane/runtime-adapter
        :core/modules/funflow/control-plane/agent-harness
        :core/modules/funflow/control-plane/replay
        :core/modules/funflow/control-plane/runner
        :core/modules/funflow/control-plane/config)

(export (import: :core/modules/funflow/control-plane/roles)
        (import: :core/modules/funflow/control-plane/failure)
        (import: :core/modules/funflow/control-plane/receipt)
        (import: :core/modules/funflow/control-plane/task)
        (import: :core/modules/funflow/control-plane/flow-strand)
        (import: :core/modules/funflow/control-plane/flow)
        (import: :core/modules/funflow/control-plane/flow-syntax)
        (import: :core/modules/funflow/control-plane/graph)
        (import: :core/modules/funflow/control-plane/strategy)
        (import: :core/modules/funflow/control-plane/policy)
        (import: :core/modules/funflow/control-plane/runtime-protocol)
        (import: :core/modules/funflow/control-plane/runtime-command-invocation)
        (import: :core/modules/funflow/control-plane/runtime-command-descriptor)
        (import: :core/modules/funflow/control-plane/runtime-adapter)
        (import: :core/modules/funflow/control-plane/agent-harness)
        (import: :core/modules/funflow/control-plane/replay)
        (import: :core/modules/funflow/control-plane/runner)
        (import: :core/modules/funflow/control-plane/config))
