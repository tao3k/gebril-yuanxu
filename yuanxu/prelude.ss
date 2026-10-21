;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core

;; Bootstrap independently of Core's Module System and its declaration macros.
(import (except-in :gerbil/core object? make-object)
        :clan/poo/object)
(export (import: :gerbil/core :clan/poo/object))
