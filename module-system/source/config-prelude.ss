;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prelude bindings are weak: explicit config imports retain ownership.
(import :gerbil/core :clan/poo/object)
(export (except-out (import: :gerbil/core) object? make-object)
        (import: :clan/poo/object))
