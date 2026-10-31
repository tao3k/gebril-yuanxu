# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""An owned, pinned Apalache session; models and decisions are never cached."""
from contextlib import contextmanager
import os
from pathlib import Path
import selectors
import shutil
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
def backend_session(progress, quint_executable):
    executable = Path(os.environ.get('QUINT_HOME', Path.home() / '.quint')) / 'apalache-dist-0.62.1/apalache/bin/apalache-mc'
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
                nonlocal last_output
                while True:
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        return
                    last_output = time.monotonic()
                    progress(chunk)
            pump = threading.Thread(target=drain, name='apalache-output', daemon=True)
            pump.start()
            # The backend prints 'running' before gRPC reflection is ready.
            # Use its pinned gRPC dependencies and reflection schema, with no
            # automatic server-start fallback or model-result reuse.
            cli = Path(shutil.which(str(quint_executable)) or quint_executable).resolve()
            client = cli.with_name('apalache.js')
            probe = """
const req = require('node:module').createRequire(process.argv[1]);
const grpc = req('@grpc/grpc-js');
const proto = req('@grpc/proto-loader').loadSync(req.resolve('./reflection.proto'),
  {keepCase:true, longs:String, enums:String, defaults:true, oneofs:true});
const Service = grpc.loadPackageDefinition(proto).grpc.reflection.v1alpha.ServerReflection;
const client = new Service('127.0.0.1:' + process.argv[2], grpc.credentials.createInsecure());
const deadline = new Date(Date.now() + Number(process.argv[3]));
const finish = (status, error) => { if(error) console.error(String(error)); client.close(); process.exit(status); };
client.waitForReady(deadline, error => {
  if(error) return finish(1, error);
  const call = client.ServerReflectionInfo({deadline});
  call.on('data', data => {
    const files = data.file_descriptor_response?.file_descriptor_proto;
    call.end(); finish(files?.length > 0 ? 0 : 1, data.error_response?.error_message);
  });
  call.on('error', error => finish(1, error));
  call.write({file_containing_symbol:'shai.cmdExecutor.CmdExecutor'});
});
"""
            ready = None
            while True:
                remaining = min(45 - (time.monotonic() - started),
                                5 - (time.monotonic() - last_output))
                if remaining <= 0 or process.poll() is not None:
                    raise TimeoutError('Apalache did not establish its pinned gRPC protocol in time: ' + (ready.stderr.decode(errors='replace')[-1200:] if ready else 'no probe result'))
                try:
                    ready = subprocess.run(['node', '-e', probe, str(client), str(port), str(int(remaining * 1000))],
                                           capture_output=True, timeout=remaining)
                except subprocess.TimeoutExpired as failure:
                    raise TimeoutError('Apalache gRPC readiness exceeded real-output deadline') from failure
                if ready.returncode == 0:
                    if process.poll() is not None:
                        raise RuntimeError('Owned Apalache exited during readiness handshake')
                    break
                time.sleep(0.05)
            progress(f'APALACHE-SESSION pid={process.pid} endpoint=127.0.0.1:{port} version=0.62.1 heap=1G grpc=ready\n'.encode())
            yield f'127.0.0.1:{port}'
        finally:
            terminate(process)
            if pump is not None:
                pump.join(timeout=1)
            process.stdout.close()
            signal.signal(signal.SIGTERM, previous)
