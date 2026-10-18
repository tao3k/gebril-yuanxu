;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :clan/poo/object-contract
        (only-in :clan/poo/mop define-type element?)
        (only-in :clan/poo/number IntegerRange)
        (only-in :clan/poo/type List)
        (only-in :core/types PooFlowContract. poo-flow-predicate-contract
                 poo-flow-classification-evidence))
(export Port PostgreSQLValueContract PostgreSQLConfigContract PostgreSQLScopeContract valid-port?)
(def Port (IntegerRange min: 1 max: 65535))
(def (valid-port? value) (element? Port value))
(def PostgreSQLValueContract
  (.cc ObjectContract. identity: 'postgresql/config-value
    responsibilities:
    (.o settings: (.cc ObjectContract. responsibilities: (.o port: Port))
        allowed-ports: (List Port))))
(define-type (PostgreSQLConfigContract @ PooFlowContract.)
  identity: 'postgresql/config
  value-contract: PostgreSQLValueContract
  .classify: (lambda (candidate context)
               (poo-flow-classification-evidence identity candidate #t '() context)))
;; Scope presence is intentionally metadata-only; it must not force payloads.
(def PostgreSQLScopeContract
  (poo-flow-predicate-contract 'postgresql/scope
    (lambda (value) (and (object? value) (.slot? value 'config) (.slot? value 'document)))
    (lambda (_v _c) '())))
