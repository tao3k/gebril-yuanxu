;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Scope comes from Types and ReleaseProfile comes from Objects.
(.def Release
  identity: 'release
  core:
  (.o requires: (.o Engine: (.o module-id: 'engine contract: Scope))
      scope-contract: Scope
      exports: (.o profile: (.cc ReleaseProfile 'engine Engine)))
  features: (.o))
