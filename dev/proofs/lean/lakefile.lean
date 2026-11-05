-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package YuanxuProof where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "da273cdc75c9d65409e3d4979a6e9856c384809f"

@[default_target]
lean_lib YuanxuProof where
  roots := #[`YuanxuProof]
