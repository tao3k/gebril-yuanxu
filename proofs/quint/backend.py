# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""An owned, pinned Apalache session; models and decisions are never cached."""
from contextlib import contextmanager
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import threading
import time


def terminate(process):
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=1)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


@contextmanager
def backend_session(progress):
    executable = Path.home() / '.quint/apalache-dist-0.62.1/apalache/bin/apalache-mc'
    if not executable.is_file():
        raise RuntimeError('prepare the pinned Apalache 0.62.1 distribution first')
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    # One compilation backend, plus the existing one-worker 1G TLC process.
    environment = dict(os.environ, JVM_ARGS='-Xmx1G')
    with subprocess.Popen([str(executable), 'server', f'--port={port}'],
                          env=environment, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, start_new_session=True) as process:
        def interrupted(signum, frame):
            raise SystemExit(128 + signum)
        previous = signal.signal(signal.SIGTERM, interrupted)
        pump = None
        try:
            started = last_output = time.monotonic()
            output = bytearray()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while b'The Apalache server is running' not in output:
                    if process.poll() is not None:
                        raise RuntimeError('Apalache exited before server readiness')
                    now = time.monotonic()
                    if now - started > 45 or now - last_output > 5:
                        raise TimeoutError('Apalache startup exceeded 45s or 5s real-output deadline')
                    for key, _ in selector.select(0.1):
                        chunk = os.read(key.fileobj.fileno(), 65536)
                        if not chunk:
                            raise RuntimeError('Apalache closed output before server readiness')
                        output.extend(chunk)
                        last_output = time.monotonic()
                        progress(chunk)
            if b'APALACHE version: 0.62.1 |' not in output:
                raise RuntimeError('Apalache server did not attest pinned version 0.62.1')
            def drain():
                while True:
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        return
                    progress(chunk)
            pump = threading.Thread(target=drain, name='apalache-output', daemon=True)
            pump.start()
            progress(f'APALACHE-SESSION pid={process.pid} endpoint=localhost:{port} version=0.62.1 heap=1G\n'.encode())
            yield f'localhost:{port}'
        finally:
            terminate(process)
            if pump is not None:
                pump.join(timeout=1)
            process.stdout.close()
            signal.signal(signal.SIGTERM, previous)
