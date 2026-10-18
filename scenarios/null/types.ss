;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        :clan/poo/object-contract
        (only-in :clan/poo/type True)
        (only-in :core/modules/json-schema/contracts ProjectionContract.)
        (only-in :core/types poo-flow-predicate-contract))
(export ScopeContract null-admission)
(def ScopeShape
  (.cc ProjectionContract.
    'constraint (.cc ObjectContract. responsibilities:
                  (.o Scenario: True provider: True types: True))
    'project
    (lambda (scope)
      (if (not (object? scope)) scope
        (.o Scenario: (.slot? scope 'Scenario)
            provider: (.slot? scope 'provider)
            types: (.slot? scope 'types))))))
(def ScopeContract
  (.cc (poo-flow-predicate-contract 'null/scope object? (lambda (_v _c) '()))
    'value-contract ScopeShape))
(def (null-admission input-type)
  (.cc (poo-flow-predicate-contract 'null/input object? (lambda (_v _c) '()))
    'value-contract
    (.cc ProjectionContract. 'constraint input-type
      'project (lambda (scenario) (.get scenario resource)))))
