;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Shared declaration-only phase binding; no class lifecycle or reflection.
(import :std/stxparam (only-in "objects.ss" poo-clos-method-bundle))
(export .defmethod-bundle %method-declaration-only)

;; All method syntax consumers must share this SAME hygienic parameter binding.
(defsyntax-parameter %method-declaration-only #f)
(defrules .defmethod-bundle ()
  ((_ name protocol method ...)
   (def name
     (syntax-parameterize ((%method-declaration-only (quote-syntax #t)))
       (poo-clos-method-bundle 'name protocol (list method ...))))))
