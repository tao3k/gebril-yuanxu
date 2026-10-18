-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package PooFlowCoreProof where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "v0.1.1"

@[default_target]
lean_lib PooFlowCoreProof where
  roots := #[`PooFlowCoreProof]
