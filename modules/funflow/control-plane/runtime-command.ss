;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: public facade for runtime command invocation and descriptors.
;;; Invariant: leaf owners keep command execution separate from manifest data.

(import :core/modules/funflow/control-plane/runtime-command-invocation
        :core/modules/funflow/control-plane/runtime-command-descriptor)

(export (import: :core/modules/funflow/control-plane/runtime-command-invocation)
        (import: :core/modules/funflow/control-plane/runtime-command-descriptor))
