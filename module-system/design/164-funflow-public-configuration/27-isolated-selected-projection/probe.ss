;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;; Isolated fixture only. No module adapter, Loader or construction hook.
(import :clan/poo/object :yuanxu/types
        (only-in :std/list/list every delete-duplicates/hash))
(include "setup.ss")
(include "selected-admission.ss")
(include "controls.ss")
