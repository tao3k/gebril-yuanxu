;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Scope comes from Types and ReleaseProfile comes from Objects.
(import (rename-in (only-in "../../modules/engine/objects.ss" ScopeValue) (ScopeValue Engine)))
(.def Release
  identity: 'release
  core:
  (.o scope-contract: Scope
      exports: (.o profile: (.cc ReleaseProfile 'engine Engine)))
  features: (.o))
