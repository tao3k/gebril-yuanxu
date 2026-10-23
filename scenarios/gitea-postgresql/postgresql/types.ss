;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :clan/poo/object-contract
        (only-in :clan/poo/mop define-type)
        (only-in :yuanxu/object-types/ports Port valid-port?)
        (only-in :clan/poo/type List)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-predicate-contract))
(export Port PostgreSQLValueContract PostgreSQLConfigContract PostgreSQLScopeContract valid-port?)
(def PostgreSQLValueContract
  (.cc ObjectContract. identity: 'postgresql/config-value
    responsibilities:
    (.o settings: (.cc ObjectContract. responsibilities: (.o port: Port))
        allowed-ports: (List Port))))
(define-type (PostgreSQLConfigContract @ YuanxuContract.)
  identity: 'postgresql/config
  value-contract: PostgreSQLValueContract)
;; Scope presence is intentionally metadata-only; it must not force payloads.
(def PostgreSQLScopeContract
  (yuanxu-predicate-contract 'postgresql/scope
    (o?/slots '(config document))))
