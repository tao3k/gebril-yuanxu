;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object)
(export ScopePrototype)
(.def ScopePrototype
  config: (error "scope requires the final Config")
  port: (.get config port))
