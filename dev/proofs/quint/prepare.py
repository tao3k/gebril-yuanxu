# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Prepare the pinned backend; this never emits a proof receipt."""
from pathlib import Path
import subprocess
import tempfile
from check import quint_executable

quint = quint_executable()
version = subprocess.check_output([quint, "--version"], text=True, timeout=5).strip()
if version != "0.33.0":
    raise SystemExit(f"expected Quint 0.33.0, got {version}")
models = Path(__file__).resolve().parent
print("QUINT-PREPARE backend=0.62.1 (not a proof receipt)", flush=True)
with tempfile.TemporaryDirectory(prefix="core-quint-prepare-") as directory:
    config = Path(directory) / "backend.json"
    config.write_text('{"workers":"1","maxHeap":"-Xmx1G"}\n')
    subprocess.run([quint, "verify", str(models / "NativeSemanticQuery.qnt"),
        "--main", "NativeSemanticQuery", "--backend", "tlc", "--apalache-version", "0.62.1",
        "--invariant", "safety", "--verbosity", "3", "--tlc-config", str(config)],
        cwd=directory, check=True, timeout=60)
print("QUINT-PREPARE-OK (not a proof receipt)", flush=True)
