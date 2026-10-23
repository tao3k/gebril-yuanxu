;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :yuanxu/types yuanxu-predicate-contract))
(export FunflowScopeContract)
(def FunflowScopeContract
  (yuanxu-predicate-contract 'funflow/scope
    (lambda (value)
      (and (object? value) (.slot? value 'prototypes)
           (every (lambda (key) (.slot? (.get value prototypes) key)) '(Task Job))))
    (lambda (_value _context) '())))
