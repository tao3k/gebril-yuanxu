# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Prepare the pinned backend; this never emits a proof receipt."""
from pathlib import Path
import subprocess
import shutil
from check import quint_executable

quint = quint_executable()
version = subprocess.check_output([quint, "--version"], text=True, timeout=5).strip()
if version != "0.33.0":
    raise SystemExit(f"expected Quint 0.33.0, got {version}")
print("QUINT-PREPARE backend=0.62.1 (not a proof receipt)", flush=True)
# Quint owns its distribution path, download and atomic unpacking. Preparation
# must not verify an unrelated business model just to trigger that download.
# The existing backend_session attests the version before any accepted check.
cli = Path(shutil.which(str(quint)) or quint).resolve()
fetch = """
const {fetchApalache} = require(process.argv[1]);
fetchApalache('0.62.1', 3).then(result => {
  if (result.isLeft()) {
    console.error(result.value); process.exitCode = 1;
  } else {
    console.log('QUINT-BACKEND-PREPARED ' + result.value);
  }
}).catch(error => { console.error(error); process.exitCode = 1; });
"""
subprocess.run(['node', '-e', fetch, str(cli.with_name('apalache.js'))],
               check=True, timeout=60)
print("QUINT-PREPARE-OK (not a proof receipt)", flush=True)
