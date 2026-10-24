# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Serial requests to the pinned Quint CLI stages; no model/result cache."""
from pathlib import Path
import json
import os
import selectors
import shutil
import signal
import subprocess
import time


class QuintCLI:
    def __init__(self, quint, mode, cwd=None):
        executable = shutil.which(quint)
        if not executable:
            raise FileNotFoundError(quint)
        self.commands = Path(executable).resolve().with_name("cliCommands.js")
        if not self.commands.is_file():
            raise RuntimeError(f"pinned Quint CLI API is missing: {self.commands}")
        self.mode, self.cwd = mode, cwd

    def __enter__(self):
        self.cancelled = False
        self.control, writer = os.pipe()
        try:
            self.process = subprocess.Popen(
                ["node", "--max-old-space-size=1024",
                 str(Path(__file__).with_name("native-cli.cjs")),
                 str(self.commands), self.mode, str(writer)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, pass_fds=(writer,),
                start_new_session=True, cwd=self.cwd)
        except BaseException:
            os.close(self.control)
            raise
        finally:
            os.close(writer)
        return self

    def request(self, args, wall=5, idle=5, emit=False):
        if self.cancelled:
            raise RuntimeError("Quint CLI worker was cancelled; start a new worker")
        started = last_output = time.monotonic()
        output, control = bytearray(), bytearray()
        self.process.stdin.write((json.dumps(args) + "\n").encode())
        self.process.stdin.flush()

        def read_output():
            nonlocal last_output
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("Quint CLI worker closed output")
            output.extend(chunk)
            last_output = time.monotonic()
            if emit:
                print(chunk.decode(errors="replace"), end="", flush=True)

        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ, "output")
            selector.register(self.control, selectors.EVENT_READ, "control")
            while not control.endswith(b"\n"):
                now = time.monotonic()
                remaining = min(wall - (now - started), idle - (now - last_output))
                if remaining <= 0:
                    # A deadline invalidates the in-flight response. Stop this
                    # owned session now, even if the caller catches TimeoutError
                    # inside the context; it cannot safely serve another request.
                    self.cancelled = True
                    self.stop()
                    raise TimeoutError(f"Quint {self.mode} exceeded {wall}s case or {idle}s real-output deadline: {args['input']}")
                for key, _ in selector.select(min(remaining, 0.1)):
                    if key.data == "output":
                        read_output()
                    else:
                        chunk = os.read(self.control, 65536)
                        if not chunk:
                            raise RuntimeError("Quint CLI worker closed result channel")
                        control.extend(chunk)
            # The native worker flushes its output before sending the result.
            # Drain already-written diagnostics before the next request starts.
            while any(key.data == "output" for key, _ in selector.select(0)):
                read_output()
        result = json.loads(control)
        if any(result.get(key) != args.get(key) for key in ("input", "main", "invariant")):
            raise RuntimeError("Quint CLI result belongs to another request")
        if result.get("status") not in (0, 1):
            raise RuntimeError("Quint CLI result has no native status")
        return result["status"], bytes(output)

    def stop(self):
        if self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.process.wait()

    def __exit__(self, kind, value, traceback):
        try:
            if kind is None and not self.cancelled:
                self.process.stdin.close()
                if self.process.wait(timeout=1) != 0:
                    raise RuntimeError("Quint CLI worker failed")
        finally:
            self.stop()
            self.process.stdin.close()
            self.process.stdout.close()
            os.close(self.control)
