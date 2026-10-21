-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package PooFlowCoreProof where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "6e6a706e14fa6f8199e4f36711440355b42ef335"

@[default_target]
lean_lib PooFlowCoreProof where
  roots := #[`PooFlowCoreProof]
