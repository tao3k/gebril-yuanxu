#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check that the real Justfile gates reject isolated compiled mutations.

No checkout source or installed prerequisite is modified. A native package
header preserves the copied module's identity; only the temporary compiled
module is placed ahead of the existing compiler inputs for each fresh worker.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "module-system/building/source-package.ss"
UNIT = "t/build-input-context-test.ss"
ROLE = "t/module-build-role-test.ss"
BAD = ("ERROR CASE", "ERROR CHECK", "ERROR HARNESS", "Heap overflow", "Stack overflow")
PARTITION = """(def inputs (append (filter (lambda (path) (not (output? path))) previous)
                     (filter output? previous)))"""
MUTATIONS = (
    ("output-first", PARTITION,
     """(def inputs (append (filter output? previous)
                     (filter (lambda (path) (not (output? path))) previous)))""",
     UNIT, r"ERROR CHECK \(load-path\)"),
    ("reversed-prerequisites", PARTITION,
     """(def inputs (append (reverse (filter (lambda (path) (not (output? path))) previous))
                     (filter output? previous)))""",
     UNIT, r"ERROR CHECK \(load-path\)"),
    ("missing-restoration", "(set-load-path! previous)", "(void)",
     UNIT, r"ERROR CHECK \(load-path\)"),
    ("accepted-input-mutation", "(unless unchanged? (refuse))", "(void)",
     ROLE, r"--- irritants: changed-compiler-input-refused"),
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path)
    parser.add_argument("--runtime-options", required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    receipt = Path(tempfile.mkdtemp(prefix="build-input-context-", dir=args.artifacts.resolve()))
    print(f"BUILD-INPUT-CONTEXT-ARTIFACTS {receipt}", flush=True)
    original = SOURCE.read_bytes()
    text = original.decode()
    results = {"source_sha256": digest(original), "runs": []}
    environment = dict(os.environ)

    def invoke(label, command, env):
        with (receipt / f"{label}.log").open("w") as log:
            status = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                                    stderr=subprocess.STDOUT).returncode
        output = (receipt / f"{label}.log").read_text(errors="replace")
        results["runs"].append({"label": label, "exit": status})
        return status, output

    def positive(label, test):
        status, output = invoke(label, ["just", "test-file", test], environment)
        if (status or any(marker in output for marker in BAD)
                or not all(marker in output for marker in ("MODULE-OK", "HARNESS-OK"))
                or not re.search(r"^OK\s*$", output, re.M)):
            raise RuntimeError(f"correct implementation failed: {label}; see {receipt}")
        print(f"BUILD-INPUT-CONTEXT-PASS {label}", flush=True)

    try:
        positive("before-order", UNIT)
        positive("before-admission", ROLE)
        for name, old, new, test, expected in MUTATIONS:
            # The restoration expression also occurs in another private helper;
            # mutate only its first occurrence in call-with-build-input-path.
            if old not in text or (name != "missing-restoration" and text.count(old) != 1):
                raise RuntimeError(f"mutation anchor changed: {name}; review its fault model")
            variant = text.replace(old, new, 1)
            source = receipt / name / "source-package.ss"
            library = receipt / name / "lib"
            library.mkdir(parents=True)
            source.write_text("package: yuanxu/module-system/building\n" + variant)
            results[name] = {"source_sha256": digest(source.read_bytes()), "test": test}
            status, _ = invoke(f"{name}-compile", [
                "timeout", "--signal=TERM", "--kill-after=5s", "120s", "gxc",
                args.runtime_options, "-O", "-d", str(library), str(source),
            ], environment)
            if status:
                raise RuntimeError(f"mutation did not compile: {name}; see {receipt}")
            env = dict(environment)
            # Preserve every existing prerequisite; this is a test-only native
            # artifact overlay, never a downstream production path workaround.
            previous = env.get("GERBIL_LOADPATH", "")
            env["GERBIL_LOADPATH"] = str(library) + (os.pathsep + previous if previous else "")
            status, output = invoke(name, ["just", "test-file", test], env)
            if (status in (0, 124, 137, 143) or status < 0
                    or "Heap overflow" in output or "Stack overflow" in output
                    or not re.search(expected, output)):
                raise RuntimeError(f"mutation survived or failed for the wrong reason: {name}; see {receipt}")
            results[name]["rejected"] = True
            print(f"BUILD-INPUT-CONTEXT-REJECTED {name} exit={status}", flush=True)
        # Fresh processes after discarding the mutation overlays use the
        # original implementation again, without a prepared scope or Context.
        positive("after-order", UNIT)
        positive("after-admission", ROLE)
        results["ok"] = True
    finally:
        results["source_unchanged"] = SOURCE.read_bytes() == original
        (receipt / "receipt.json").write_text(json.dumps(results, indent=2) + "\n")
        if not results["source_unchanged"]:
            raise RuntimeError("checkout source changed during mutation qualification")
    print("BUILD-INPUT-CONTEXT-MUTATIONS-OK mutations=4 source-unchanged=true", flush=True)


if __name__ == "__main__":
    main()
