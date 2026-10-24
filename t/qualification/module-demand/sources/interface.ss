;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Module
  identity: 'application
  core:
  (.o (:: core-self [])
    requires: (.o Database: (.o module-id: 'database contract: ScopeContract))
    roles: (make-role-bindings)
    config: Config
    scope-contract: (.cc ScopeContract source-inputs: SourceRows)
    exports: (.cc ScopePrototype config: config))
  features: (.o)
  scope: ((.get core link) (.o Database: (.o))))
