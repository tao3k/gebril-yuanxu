;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Existing Module values bound to SourceRefs; construction never loads them.
(import (only-in :clan/poo/mop define-type Object)
        (only-in :clan/poo/type Record))
(export ModuleSourceBinding)

(define-type ModuleSourceBinding
  (Record source: [Object] module: [Object]))
