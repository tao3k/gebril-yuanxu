;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object)
(export Config)
;; Inert operational defaults; a command is supplied by the caller.
(def Config
  (.o directory: #f environment: (.o) timeout: #f idle-timeout: #f
      progress: #f log: #f check-status: #t))
