#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail
source_root="$(cd "$(dirname "$0")/../../.." && pwd)"
bootstrap_tmp="$(mktemp -d)"
trap 'rm -rf "$bootstrap_tmp"' EXIT
mkdir -p "$bootstrap_tmp/source/core" "$bootstrap_tmp/gerbil"
# Source-only checkout: no dependency on the caller's uncommitted files or build.
git -C "$source_root" archive HEAD | tar -x -C "$bootstrap_tmp/source/core"
cp -R "${GERBIL_PATH:-$source_root/.gerbil}/lib" "$bootstrap_tmp/gerbil/lib"
rm -rf "$bootstrap_tmp/gerbil/lib/core"
rm -f "$bootstrap_tmp/gerbil/lib/static/"core__*
export GERBIL_PATH="$bootstrap_tmp/gerbil"
export GERBIL_LOADPATH="$bootstrap_tmp/source"
# Bounded serial compilation is a correctness control, not a throughput claim.
export GERBIL_BUILD_CORES=1
cd "$bootstrap_tmp/source/core"
just bootstrap
if [ -e "$GERBIL_PATH/lib/core/modules/json-schema" ]; then
  echo 'Bootstrap unexpectedly built the selected application Module.' >&2
  exit 1
fi
just test-file t/module-bootstrap-test.ss
echo 'BOOTSTRAP-OK source-only Core tool -> init -> JsonSchema -> build entry'
