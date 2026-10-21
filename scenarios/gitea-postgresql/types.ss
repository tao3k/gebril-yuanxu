;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :yuanxu/types yuanxu-predicate-contract))
(export ServiceScopeContract ApplicationScopeContract)
(def ServiceScopeContract
  (yuanxu-predicate-contract 'application/service-scope
    (o?/slots '(config document types))))
(def ApplicationScopeContract
  (yuanxu-predicate-contract 'application/scope
    (o?/slots '(Scenario types))))
