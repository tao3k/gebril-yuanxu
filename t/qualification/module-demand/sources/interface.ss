;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Module
  identity: 'application
  core:
  (.o (:: core-self [])
    roles: (make-role-bindings)
    config: Config
    scope-contract: ScopeContract
    application-contract: (.cc ApplicationContract source-inputs: SourceRows)
    exports: (.cc ScopePrototype config: config))
  features: (.o)
  scope: (.get core exports))
