;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :core/types poo-flow-predicate-contract))
(export ServiceScopeContract ApplicationScopeContract)
(def ServiceScopeContract
  (poo-flow-predicate-contract 'application/service-scope
    (lambda (value) (and (object? value) (.slot? value 'config)
                        (.slot? value 'document) (.slot? value 'types)))
    (lambda (_v _c) '())))
(def ApplicationScopeContract
  (poo-flow-predicate-contract 'application/scope
    (lambda (value) (and (object? value) (.slot? value 'Scenario) (.slot? value 'types)))
    (lambda (_v _c) '())))
