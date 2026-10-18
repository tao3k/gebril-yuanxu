;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Gitea
  identity: 'services/gitea
  core:
  (.o requires: (.o)
      scope-contract: GiteaScopeContract
      exports:
      (.o config: Config document: Document application: gitea-application
          policy: (gitea-policy Config Document)
          types: (.o Application: ApplicationContract Config: GiteaConfigContract)))
  features: (.o))
