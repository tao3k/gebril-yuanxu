;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def (Module module-self [])
  identity: 'application
  core:
  (.o (:: core-self [])
    requires: (.o Database: (.o module-id: 'database contract: ScopeContract))
    roles: (make-role-bindings)
    config: Config
    scope-contract: (.cc ScopeContract source-inputs: SourceRows)
    exports: (.cc ScopePrototype config: config))
  features: (.o)
  scope: ((.get module-self core link) (.o Database: (.o))))
