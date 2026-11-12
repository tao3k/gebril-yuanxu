-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package YuanxuProof where
  version := v!"0.1.0"

require LeanPoo from git
  "https://github.com/tao3k/lean-poo.git"
  @ "59aae5dbef4daccb01b6ec40b1880c1ae1abb7c8"

@[default_target]
lean_lib YuanxuProof where
  roots := #[`YuanxuProof]
