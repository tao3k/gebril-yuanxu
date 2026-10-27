;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Catalog fields describe existing values; validation must not load a source.
(import (only-in :clan/poo/mop define-type)
        (only-in :clan/poo/type Record List Symbol)
        (only-in :yuanxu/module-system/source/types ModuleSourceBinding))
(export ModuleSourceBinding ModuleCatalog)

(define-type ModuleCatalog
  (Record name: [Symbol] entries: [(List ModuleSourceBinding)]))
