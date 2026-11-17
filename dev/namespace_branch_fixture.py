# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Create the bounded, metadata-only corpus used by namespace branch probes."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--size", type=int, default=1000)
    args = parser.parse_args()
    if not 1 <= args.size <= 1000:
        parser.error("this qualification corpus requires 1..1000 paths")
    args.root.mkdir(parents=True, exist_ok=False)
    clauses = []
    for number in range(args.size):
        group, name = f"g{number}", f"m{number}"
        leaf = args.root / "modules" / group / name
        leaf.mkdir(parents=True)
        # Accidental publication interpretation must fail, rather than silently
        # contaminating the metadata-only timing with business evaluation.
        (leaf / "interface.ss").write_text("((publication must remain unread\n")
        clauses.append(f":{group} ({name})")
    (args.root / "init.ss").write_text(
        '(yuanxu! :load-modules "./modules" mode: explicit rename: Lab '
        + " ".join(clauses)
        + ")\n"
    )


if __name__ == "__main__":
    main()
