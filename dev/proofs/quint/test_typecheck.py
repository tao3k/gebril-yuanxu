# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Compare the retained native checker with the pinned CLI, including mutations."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("core_quint_check", Path(__file__).with_name("check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
QUINT = check.quint_executable()


class TypecheckTests(unittest.TestCase):
    def test_wall_and_real_output_deadlines_are_enforced(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Sample.qnt"
            source.write_text("module Sample { pure val answer: int = 1 }")
            for limits in ({"wall": 0, "idle": 5}, {"wall": 5, "idle": 0}):
                with self.subTest(limits=limits), check.QuintCLI(QUINT, "typecheck") as runtime:
                    with self.assertRaises(TimeoutError):
                        runtime.request({"input": str(source)}, **limits)
                    self.assertIsNotNone(runtime.process.poll())
                    with self.assertRaisesRegex(RuntimeError, "worker was cancelled"):
                        runtime.request({"input": str(source)})

    def test_native_cli_agreement(self):
        cases = [
            ("module Sample { pure val answer: int = 1 }", True),
            ("module Sample { pure val answer: int = true }", False),
            ("module Sample { pure val = }", False),
            ("module Sample { var n: int pure val answer = n }", False),
        ]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Sample.qnt"
            for text, accepted in cases:
                with self.subTest(text=text):
                    source.write_text(text)
                    cli = subprocess.run([QUINT, "typecheck", str(source)],
                                         capture_output=True, timeout=5)
                    self.assertEqual(cli.returncode == 0, accepted)
                    if accepted:
                        check.typecheck_entries(QUINT, [source])
                    else:
                        with self.assertRaisesRegex(RuntimeError, "typecheck failed"):
                            check.typecheck_entries(QUINT, [source])

    def test_import_mutation_between_requests_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            support = Path(directory) / "Support.qnt"
            source = Path(directory) / "Sample.qnt"
            source.write_text('module Sample { import Support.* from "./Support"\n'
                              'pure val answer: int = value }')
            support.write_text("module Support { pure val value: int = 1 }")

            def entries():
                yield source
                support.write_text("module Support { pure val value: int = true }")
                yield source

            with self.assertRaisesRegex(RuntimeError, "typecheck failed"):
                check.typecheck_entries(QUINT, entries())


if __name__ == "__main__":
    unittest.main()
