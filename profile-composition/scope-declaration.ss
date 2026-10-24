;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Syntax-only inspection shared by the selector and object authoring frame.
(import :gerbil/expander)
(export bounded-module-use-parts)

(def (bounded-module-use-parts form use-module-id)
  (syntax-case form ()
    ((head module-name marker alias body)
     (and (identifier? #'head)
          (free-identifier=? #'head use-module-id)
          (identifier? #'module-name)
          (identifier? #'marker)
          (free-identifier=? #'marker #'as)
          (identifier? #'alias)
          (pair? (syntax->list #'body)))
     (list #'module-name #'alias #'body))
    (_ #f)))
