;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Role bindings refine the package language, including its compile-time phases.
;;; Explicit role imports remain authoritative over these weak prelude bindings.
(import :gerbil/core
        :clan/poo/object
        (rename-in (only-in :tao3k/yuanxu/module-system/source/declaration .def)
                   (.def role-.def))
        (phi: +1 :gerbil/core)
        (phi: +2 :gerbil/core))
(export (except-out (import: :gerbil/core) object? make-object)
        (except-out (import: :clan/poo/object) .def)
        (phi: +1 (import: :gerbil/core))
        (phi: +2 (import: :gerbil/core))
        (phi: 1 load-module)
        (rename-out role-.def (role-.def .def)))
