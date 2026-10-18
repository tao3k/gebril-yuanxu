# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check Core-owned finite Quint models and matched counterexample controls."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time

CASES = [
    ("NativeSemanticQuery", "safety", False),
    ("GraphOperations_none", "safety", False),
    ("GraphOperations_reverseOrder", "OrderedPayload", True),
    ("GraphOperations_wrongTarget", "PathIdentity", True),
    ("GraphOperations_orphanDelete", "StructuralClosure", True),
    ("GraphOperations_replay", "OrderedPayload", True),
    ("GraphOperations_fixedPoint", "HonestReceipt", True),
]
COUNTS = re.compile(rb"([\d,]+) states generated, ([\d,]+) distinct states.*?([\d,]+) states left on queue")


def run(command, cwd):
    started = last_output = time.monotonic()
    output = bytearray()
    with subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, start_new_session=True) as process:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while selector.get_map():
                    now = time.monotonic()
                    if now - started > 45 or now - last_output > 5:
                        raise TimeoutError("Quint exceeded 45s case or 5s real-output deadline")
                    for key, _ in selector.select(0.1):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if chunk:
                            output.extend(chunk)
                            last_output = time.monotonic()
                            print(chunk.decode(errors="replace"), end="", flush=True)
                        else:
                            selector.unregister(key.fileobj)
            status = process.wait(timeout=1)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
    return status, bytes(output)


def scheme(value):
    if isinstance(value, bool):
        return "#t" if value else "#f"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, dict):
        return "(" + " ".join("(" + key + " . " + scheme(item) + ")" for key, item in value.items()) + ")"
    if isinstance(value, list):
        return "(" + " ".join(map(scheme, value)) + ")"
    return str(value)


def quint_executable():
    local = Path(__file__).resolve().parent / "node_modules/.bin/quint"
    return os.environ.get("QUINT_BIN", str(local) if local.exists() else shutil.which("quint"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quint", default=quint_executable())
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    args.receipt.unlink(missing_ok=True)
    version = subprocess.check_output([args.quint, "--version"], text=True, timeout=5).strip()
    if version != "0.33.0":
        raise SystemExit(f"expected Quint 0.33.0, got {version}")
    models = Path(__file__).resolve().parent
    core = models.parents[1]
    bound = (sorted(models.glob("*.qnt")) + sorted((core / "graph").glob("*.ss"))
             + sorted((core / "module-system/schema/support").glob("*.ss"))
             + [core / "t/graph-operations-test.ss", core / "module-system/source/projection.ss"])
    def digests():
        return {str(p.relative_to(core)): hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
    sources = digests()
    lean = core / "proofs/lean/PooFlowCoreProof/Graph/Operations.lean"
    digest = "sha256:" + hashlib.sha256((models / "GraphOperations.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{digest}"' not in lean.read_text():
        raise AssertionError("Lean retains a stale GraphOperations Quint source binding")
    bound.append(lean)
    sources = digests()
    for source in sorted(models.glob("*.qnt")):
        subprocess.run([args.quint, "typecheck", str(source)], check=True, timeout=5)
    print("QUINT-TYPECHECK-OK", flush=True)
    results = []
    with tempfile.TemporaryDirectory(prefix="core-quint-") as directory:
        work = Path(directory)
        for source in models.glob("*.qnt"):
            shutil.copyfile(source, work / source.name)
        config = work / "backend.json"
        config.write_text('{"workers":"1","maxHeap":"-Xmx1G"}\n')
        for model, invariant, negative in CASES:
            print(f"QUINT-CHECK {model} {invariant}", flush=True)
            status, output = run([args.quint, "verify", str(work / (model + ".qnt")),
                "--main", model, "--backend", "tlc", "--apalache-version", "0.62.1",
                "--invariant", invariant, "--tlc-config", str(config), "--verbosity", "3"], work)
            counts = COUNTS.search(output)
            accepted = ((status == 1 and b"Error: Invariant q_inv is violated." in output
                         and b"[violation] Found an issue" in output
                         and b"error: found a counterexample" in output) if negative else
                        (status == 0 and b"[ok] No violation found" in output and counts is not None
                         and counts[3].replace(b",", b"") == b"0"))
            if not accepted or counts is None:
                raise AssertionError(f"unexpected verifier result: {model}/{invariant}, exit={status}")
            results.append({"model": model, "invariant": invariant, "negative": negative,
                "exit": status, "generated-states": int(counts[1].replace(b",", b"")),
                "distinct-states": int(counts[2].replace(b",", b"")),
                "output-sha256": hashlib.sha256(output).hexdigest()})
            print(f"QUINT-OK {model}", flush=True)
    if sources != digests():
        raise AssertionError("bound sources changed during qualification")
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(scheme({"schema": "poo-flow.quint-proof.v1", "quint-version": version,
        "backend": "tlc", "apalache-version": "0.62.1", "sources-sha256": sources,
        "cases": results}) + "\n")
    print(f"QUINT-QUALIFICATION-OK {len(results)} cases", flush=True)


if __name__ == "__main__":
    main()
