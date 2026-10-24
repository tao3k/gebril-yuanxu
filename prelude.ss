;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
package: tao3k/yuanxu

;; POO owns the ordinary language surface. Compile-time POO construction uses
;; an explicit for-syntax import rather than duplicating its entire closure.
;; Bootstrap independently of Core's Module System and its declaration macros.
(import (except-in :gerbil/core object? make-object)
        :clan/poo/object
        (phi: +1 :gerbil/core)
        (phi: +2 :gerbil/core))
(export (import: :gerbil/core :clan/poo/object)
        (phi: +1 (import: :gerbil/core))
        (phi: +2 (import: :gerbil/core)))
