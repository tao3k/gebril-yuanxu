;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract))
(def Scope (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '())))
(export Scope)
