;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :core/types poo-flow-predicate-contract))
(export ServiceScopeContract ApplicationScopeContract)
(def ServiceScopeContract
  (poo-flow-predicate-contract 'application/service-scope
    (o?/slots '(config document types))))
(def ApplicationScopeContract
  (poo-flow-predicate-contract 'application/scope
    (o?/slots '(Scenario types))))
