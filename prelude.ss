;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
package: tao3k/yuanxu

;; POO owns the ordinary language surface. Compile-time POO construction uses
;; an explicit for-syntax import rather than duplicating its entire closure.
;; Declaration syntax and deferred loaders are owned by `:tao3k/yuanxu/lang`;
;; new downstream packages should keep default `:gerbil/core` and explicitly
;; import `:tao3k/yuanxu/lang` + `:clan/poo/object` instead of setting a
;; package-wide `prelude: :tao3k/yuanxu/prelude`.
(import :gerbil/core
        :clan/poo/object
        (only-in :clan/poo/mop .new)
        "./lang.ss"
        (phi: +1 :gerbil/core)
        (phi: +2 :gerbil/core))
;; Gerbil's reexports are weak; the direct POO constructors remain authoritative.
;; Filter the public exports, not the import-set: except-in flattens the entire
;; runtime Core dependency into individual aliases for Make to revisit.
(export (except-out (import: :gerbil/core) object? make-object)
        (import: :clan/poo/object)
        .new
        (import: "./lang.ss")
        (phi: +1 (import: :gerbil/core))
        (phi: +2 (import: :gerbil/core)))
