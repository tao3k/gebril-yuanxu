;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Ordinary Gerbil package prelude; explicit role imports remain authoritative.
(import (except-in :gerbil/core object? make-object)
        (except-in :clan/poo/object .def)
        (only-in :core/module-system/source/declaration .def))
(export (import: :gerbil/core :clan/poo/object)
        ;; Compiled role interfaces load their macro code at phase one.
        (phi: 1 load-module)
        .def)
