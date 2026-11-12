;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
package: tao3k/yuanxu

;; POO owns the ordinary language surface. Compile-time POO construction uses
;; an explicit for-syntax import rather than duplicating its entire closure.
;; Declaration syntax bootstraps independently; its implementation is demanded
;; through a native import in the consumer, never during language bootstrap.
(import :gerbil/core
        :clan/poo/object
        (only-in :clan/poo/mop .new)
        "./module-system/selection/init-syntax.ss"
        (phi: +1 :gerbil/core)
        (phi: +2 :gerbil/core))
;; Gerbil's reexports are weak; the direct POO constructors remain authoritative.
;; Filter the public exports, not the import-set: except-in flattens the entire
;; runtime Core dependency into individual aliases for Make to revisit.
(export (except-out (import: :gerbil/core) object? make-object)
        (import: :clan/poo/object)
        .new
        yuanxu!
        (phi: +1 (import: :gerbil/core))
        (phi: +2 (import: :gerbil/core)))
