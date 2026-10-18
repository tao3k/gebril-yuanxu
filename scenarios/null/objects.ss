;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :core/modules/opentofu/execution OpenTofuExecution.))
(export Scenario)
(.def (Scenario @ OpenTofuExecution. message)
  message: "hello from POO Flow"
  resource: (let (text message) (.o triggers: (.o message: text)))
  provider-name: 'null resource-kind: 'null_resource resource-name: "hello")
