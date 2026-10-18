;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One declarative publication. The admitted role wrapper owns compiler imports.
(.def OpenTofu
  identity: 'opentofu
  core:
  (.o requires: (.o Nix: (.o module-id: 'nix contract: NixScopeContract)
                    JsonSchema: (.o module-id: 'json-schema contract: JsonSchemaScopeContract))
      scope-contract: OpenTofuScopeContract
      exports: OpenTofuScope.
      configuration-build: Build)
  features: (.o))
