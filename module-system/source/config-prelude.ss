;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prelude bindings are weak: explicit config imports retain ownership.
(import (except-in :gerbil/core object? make-object) :clan/poo/object)
(export (import: :gerbil/core :clan/poo/object))
