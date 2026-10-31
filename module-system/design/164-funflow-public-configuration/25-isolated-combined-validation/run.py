# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Rebuild a fresh, exact-source Gerbil fixture; never install/repair packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--interpreter', default='/opt/homebrew/bin/gxi')
    parser.add_argument('--label', default='native')
    args = parser.parse_args()
    if not args.label.replace('-', '').replace('_', '').isalnum():
        parser.error('label must contain only letters, digits, hyphens or underscores')
    artifacts = Path(__file__).resolve().parent
    repo = artifacts.parents[4]
    lock_path = artifacts.parent / '21-scheme-dfs-admission-correspondence/receipt.json'
    lock = json.loads(lock_path.read_text())
    log_path = artifacts / f'{args.label}.log'
    receipt_path = artifacts / f'{args.label}-receipt.json'
    if log_path.exists() or receipt_path.exists():
        parser.error('refusing to overwrite an existing receipt; choose a fresh label')

    root = Path(tempfile.mkdtemp(prefix='agenticailab-combined-', dir='/private/tmp'))
    source_hashes = {}
    prefix = f"gerbil-poo-{lock['pinned_POO_revision']}/"
    with tarfile.open(args.archive) as archive:
        for relative, expected in lock['pinned_POO_source_sha256'].items():
            data = archive.extractfile(prefix + relative).read()
            if digest(data) != expected:
                raise ValueError(f'pinned source hash mismatch: {relative}')
            target = root / 'clan/poo' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            source_hashes[f'clan/poo/{relative}'] = digest(data)
        # Relative ./support imports require the original package identity.
        data = archive.extractfile(prefix + 'gerbil.pkg').read()
        if data != b';; Prototype Object Orientation for Gerbil\n(package: clan/poo)\n':
            raise ValueError('unexpected pinned POO package identity')
        (root / 'clan/poo/gerbil.pkg').write_bytes(data)
        source_hashes['clan/poo/gerbil.pkg'] = digest(data)

    core = (repo / 'core/types.ss').read_bytes()
    if digest(core) != lock['core_types_sha256']:
        raise ValueError('Core types differs from the recorded source; requalify explicitly')
    (root / 'yuanxu').mkdir()
    (root / 'yuanxu/types.ss').write_bytes(core)
    # Test-source package declaration only: no dependency install or Loader.
    package = b'(package: yuanxu)\n'
    (root / 'yuanxu/gerbil.pkg').write_bytes(package)
    source_hashes['yuanxu/types.ss'] = digest(core)
    source_hashes['yuanxu/gerbil.pkg'] = digest(package)
    (root / 'home').mkdir()
    env = os.environ.copy()
    env.update(GERBIL_PATH=str(root / 'home'), GERBIL_LOADPATH=str(root))
    command = [args.interpreter, str(artifacts / 'probe.ss')]
    start = time.monotonic()
    timed_out = False
    try:
        result = subprocess.run(command, env=env, capture_output=True, timeout=60)
        output = result.stdout + result.stderr
        code = result.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        output = (error.stdout or b'') + (error.stderr or b'')
        code = 124
    elapsed = time.monotonic() - start
    log_path.write_bytes(output)
    version = subprocess.run([args.interpreter, '-v'], capture_output=True, timeout=10)
    receipt = {
        'scope': 'native-combination-and-test-local-selected-closure-no-module-adapter-no-loader',
        'pinned_POO_revision': lock['pinned_POO_revision'],
        'source_hashes': source_hashes,
        'archive_sha256': digest(args.archive.read_bytes()),
        'lock_receipt_sha256': digest(lock_path.read_bytes()),
        'probe_sha256': digest((artifacts / 'probe.ss').read_bytes()),
        'runner_sha256': digest(Path(__file__).read_bytes()),
        'repo_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'core_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo / 'core', text=True).strip(),
        'interpreter': str(Path(args.interpreter).resolve()),
        'version': (version.stdout + version.stderr).decode().strip(),
        'environment': {'GERBIL_PATH': str(root / 'home'), 'GERBIL_LOADPATH': str(root)},
        'command': command,
        'timeout_seconds': 60,
        'timed_out': timed_out,
        'exit': code,
        'elapsed_seconds': round(elapsed, 3),
        'log_sha256': digest(output),
        'native_construction_capture_implemented': False,
        'dependency_discovery_completeness_proved': False,
    }
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(output.decode(), end='')
    print(f'receipt: {receipt_path}')
    raise SystemExit(code)


if __name__ == '__main__':
    main()
