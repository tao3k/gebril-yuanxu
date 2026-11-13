;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Concrete service endpoint ports; binding port zero needs a separate policy.
(import (only-in :clan/poo/number IntegerRange)
        (only-in :clan/poo/mop element?))
(export Port valid-port?)
(def Port (IntegerRange min: 1 max: 65535))
(def (valid-port? value) (element? Port value))
