# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Materialize real role sources for the 13.35 native downstream gate."""

import argparse
import json
import shutil
from pathlib import Path


def generate(root: Path, profile: bool = False) -> None:
    root.mkdir(parents=True, exist_ok=False)
    producer = root / "producer"

    def write(path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    write(producer / "gerbil.pkg",
          "(package: yuanxu-thousand-library prelude: :tao3k/yuanxu/prelude)\n")
    # This package supplies a source catalog, not a default selection of owners.
    write(producer / "build.ss",
          "#!/usr/bin/env gxi\n(import :std/build-script)\n(defbuild-script '())\n")
    (producer / "build.ss").chmod(0o755)
    write(producer / ".gitignore", "manifest.ss\n")
    write(producer / "init.ss",
          '(yuanxu! source: "./modules" mode: explicit '
          + " ".join(f"(module-{n})" for n in range(1000)) + ")\n")
    for number in range(1000):
        owner = producer / "modules" / f"module-{number}"
        write(owner / "types.ss", """(import (only-in :clan/poo/mop Type.)
  (only-in :clan/poo/object object?))
(def ScopeContract (.cc Type. identity: 'thousand/scope .element?: object?))
(export ScopeContract)
""")
        write(owner / "objects.ss", """(import (only-in :clan/poo/object .def .get with-slot-dependencies))
(def evaluations 0)
(.def (Scope. scope [] config)
  plan: (with-slot-dependencies scope
          (lambda () (set! evaluations (1+ evaluations)) (list (.get config port))))
  computations: (lambda () evaluations)
  unselected: (error "unselected business value forced"))
(export Scope.)
""".replace("(def evaluations 0)",
              "(def evaluations (error \"unselected Objects initializer ran\"))"
              if number > 1 else "(def evaluations 0)"))
        write(owner / "config.ss", "(def Config (error \"unselected Config initializer ran\"))\n"
              if number > 1 else "(def Config (.o port: 5432))\n")
        requires = "(.o)" if number == 0 else "(.o Shared: (.o module-id: 'module-0 contract: ScopeContract))"
        build = " projections: (list Build)" if number == 1 else ""
        tags = (" tags: '(security)" if number == 1 else " tags: '(other)") if profile else ""
        write(owner / "interface.ss", f"""(.def Module identity: 'module-{number}{tags}
  core: (.o requires: {requires} scope-contract: ScopeContract
    exports: (.o (:: @ Scope.) config: Config){build})
  features: (.o unused: (error "unselected Feature forced")))
""")
    # A genuine owner-local native target. Its C compilation fails if the
    # selected owner's compiler options are lost in cross-package projection.
    write(producer / "modules/module-1/build.ss", """(def Build
  (.o kind: 'module/build
      roots: '((gxc: "support" "-cc-options" "-DYUANXU_THOUSAND_OWNER=1"))))
""")
    write(producer / "modules/module-1/support.ss", """(begin-foreign
  (c-declare "#ifndef YUANXU_THOUSAND_OWNER\n#error selected owner compiler option missing\n#endif"))
(def owner-support 1)
(export owner-support)
""")
    consumer = root / "consumer"
    templates = Path(__file__).resolve().parent.parent / "t/qualification/selected-packages/thousand-consumer"
    for source in templates.iterdir():
        if source.is_file() and source.name != "scope-control.ss":
            text = source.read_text()
            if profile and source.name == "use.ss":
                text = text.replace("'(module-0 module-1)", "'(module-1)", 1)
            write(consumer / source.name, text)
    window = json.dumps(str(producer / "modules"), ensure_ascii=False)
    selection = "mode: auto rename: Corpus profile: security" if profile else (
        "mode: explicit rename: Corpus (module-0) (module-1)"
    )
    write(consumer / "init.ss", f'(yuanxu! :load-modules {window} {selection})\n')
    control = root / "scope-control"
    write(control / "gerbil.pkg",
          "(package: yuanxu-thousand-scope-control prelude: :tao3k/yuanxu/prelude)\n")
    write(control / "init.ss",
          f'(yuanxu! :load-modules {window} mode: explicit rename: Corpus (module-0) (module-1) (module-2))\n')
    write(control / "use.ss", (templates / "scope-control.ss").read_text())
    missing = root / "missing-provider"
    for source in consumer.iterdir():
        if source.name != "init.ss":
            write(missing / source.name, source.read_text())
    write(missing / "init.ss",
          f'(yuanxu! :load-modules {window} mode: explicit rename: Corpus (module-1))\n')
    shutil.copytree(templates.parent / "package-consumer", root / "package-consumer")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--profile", action="store_true")
    args = parser.parse_args()
    generate(args.root, args.profile)
