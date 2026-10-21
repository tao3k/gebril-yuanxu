#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
# Exercise the same daemon store used by native publication qualification.
set -euo pipefail
command -v nix-store
nix-store --version
probe=$(mktemp -d "${TMPDIR:-/tmp}/yuanxu-nix-store.XXXXXX")
trap 'rm -rf "$probe"' EXIT
printf '%s\n' 'yuanxu native publication store probe' > "$probe/receipt"
store_root=$(timeout 120 nix-store --store daemon --add "$probe")
timeout 120 nix-store --store daemon --check-validity "$store_root"
timeout 120 nix-store --store daemon --verify-path "$store_root"
cmp "$probe/receipt" "$store_root/receipt"
printf 'NIX-STORE-OK %s\n' "$store_root"
