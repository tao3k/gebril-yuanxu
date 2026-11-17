;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .def))
(.def Gitea
  identity: 'services/gitea
  core:
  (.o scope-contract: GiteaScopeContract
      exports: GiteaScope)
  features: (.o))
