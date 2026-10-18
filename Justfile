# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# V19 std/make defaults to zero workers unless this is explicitly provided.
export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", `getconf _NPROCESSORS_ONLN`)

gerbil_test_max_heap := env_var_or_default("GERBIL_TEST_MAX_HEAP", "1G")
gerbil_test_debug := env_var_or_default("GERBIL_TEST_DEBUG", "q")
gerbil_test_runtime_options := "-:max-heap=" + gerbil_test_max_heap + ",debug=" + gerbil_test_debug

default:
    @just --list

build:
    GERBIL_BUILD_VERBOSE=1 env -u SDKROOT gerbil build

# The SDK env dispatcher spawns its command; repeat VM flags in the child.
test-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ path }}"
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gerbil {{ gerbil_test_runtime_options }} test "{{ path }}" 2>&1 | tee "$log"
    if grep -E 'ERROR (CHECK|CASE|HARNESS)|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -F 'MODULE-OK {{ path }}' "$log" >/dev/null
    grep -F 'HARNESS-OK' "$log" >/dev/null
    grep -x 'OK' "$log" >/dev/null

# Compile a complete gerbil-poo candidate checkout without injecting Core patches.
test-slot-read-replay:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${GERBIL_POO_SOURCE:?set to a complete gerbil-poo candidate checkout}"
    export CORE_REPLAY_ROOT="${CORE_REPLAY_ROOT:-$(mktemp -d /private/tmp/core-slot-replay-XXXXXX)}"
    export CORE_REPLAY_CORE="$(pwd)/"
    mkdir -p "$CORE_REPLAY_ROOT/source/clan" "$CORE_REPLAY_ROOT/lib"
    test -f "$GERBIL_POO_SOURCE/object.ss"
    test -d "$GERBIL_POO_SOURCE/.git" || git -C "$GERBIL_POO_SOURCE" rev-parse --git-dir >/dev/null
    test ! -e "$CORE_REPLAY_ROOT/source/clan/poo"
    cp -R "$GERBIL_POO_SOURCE" "$CORE_REPLAY_ROOT/source/clan/poo"
    git -C "$GERBIL_POO_SOURCE" rev-parse HEAD > "$CORE_REPLAY_ROOT/dependency-head"
    shasum -a 256 "$CORE_REPLAY_ROOT/source/clan/poo/object.ss" > "$CORE_REPLAY_ROOT/dependency-source.sha256"
    echo "ISOLATED-REPLAY $CORE_REPLAY_ROOT"
    just test-slot-read-replay-resume "$CORE_REPLAY_ROOT"

test-slot-read-replay-resume directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_REPLAY_ROOT="{{ directory }}"
    export CORE_REPLAY_CORE="$(pwd)/"
    (cd "$CORE_REPLAY_ROOT/source/clan/poo"; rg --files -0 -g '*.ss' -g '*.scm' | sort -z | xargs -0 shasum -a 256) > "$CORE_REPLAY_ROOT/dependency-source.sha256"
    log="$(mktemp "$CORE_REPLAY_ROOT/compile-XXXXXX.log")"
    GERBIL_PATH="${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}" GERBIL_LOADPATH="$CORE_REPLAY_ROOT/lib:$CORE_REPLAY_ROOT/source:$(pwd):${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}/lib" env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/slot-read-replay/compile.ss > "$log" 2>&1
    log="$(mktemp "$CORE_REPLAY_ROOT/test-XXXXXX.log")"
    GERBIL_PATH="${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}" GERBIL_LOADPATH="$CORE_REPLAY_ROOT/lib:$(pwd):${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}/lib" just test-file t/slot-read-replay-test.ss 2>&1 | tee "$log"

# Opt-in read-cost gates; retain the same pre-import heap fence and watchdog.
compile-slot-read-costs directory file:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_REPLAY_ROOT="{{ directory }}"
    export CORE_REPLAY_CORE="$(pwd)/"
    export CORE_REPLAY_COMPILE_FILE="{{ file }}"
    (cd "$CORE_REPLAY_ROOT/source/clan/poo"; rg --files -0 -g '*.ss' -g '*.scm' | sort -z | xargs -0 shasum -a 256) > "$CORE_REPLAY_ROOT/dependency-source.sha256"
    log="$(mktemp "$CORE_REPLAY_ROOT/cost-compile-XXXXXX.log")"
    GERBIL_LOADPATH="$CORE_REPLAY_ROOT/lib:$CORE_REPLAY_ROOT/source:$(pwd):$HOME/.gerbil/lib" env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/slot-read-replay/compile.ss > "$log" 2>&1

test-slot-read-costs directory file label:
    #!/usr/bin/env bash
    set -euo pipefail
    POO_READ_COST_LABEL="{{ label }}" GERBIL_LOADPATH="{{ directory }}/lib:{{ directory }}/source:$(pwd):$HOME/.gerbil/lib" just test-file "{{ file }}"

# Body-only hook correction: keep dependents only with unchanged interface bindings.
test-slot-read-replay-object directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_REPLAY_ROOT="{{ directory }}"
    export CORE_REPLAY_CORE="$(pwd)/"
    cp "$CORE_REPLAY_ROOT/lib/clan/poo/object.ssi" "$CORE_REPLAY_ROOT/object-before.ssi"
    (cd "$CORE_REPLAY_ROOT/source/clan/poo"; rg --files -0 -g '*.ss' -g '*.scm' | sort -z | xargs -0 shasum -a 256) > "$CORE_REPLAY_ROOT/dependency-source.sha256"
    log="$(mktemp "$CORE_REPLAY_ROOT/object-XXXXXX.log")"
    CORE_REPLAY_OBJECT_ONLY=yes GERBIL_PATH="${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}" GERBIL_LOADPATH="$CORE_REPLAY_ROOT/lib:$CORE_REPLAY_ROOT/source:$(pwd):${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}/lib" env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/slot-read-replay/compile.ss > "$log" 2>&1
    just test-slot-read-replay-interface "$CORE_REPLAY_ROOT"

test-slot-read-replay-interface directory:
    CORE_REPLAY_ROOT="{{ directory }}" timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/slot-read-replay/interface-check.ss

test-slot-read-replay-regression directory:
    #!/usr/bin/env bash
    set -euo pipefail
    qualification_root="{{ directory }}"
    for file in scenarios/gitea-postgresql/tests/config-test.ss t/gitea-postgresql-publication-test.ss t/gitea-json-configuration-test.ss t/gitea-postgresql-relocation-test.ss; do
      log="$(mktemp "$qualification_root/regression-XXXXXX.log")"
      GERBIL_PATH="${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}" GERBIL_LOADPATH="$qualification_root/lib:$(pwd):${GERBIL_TEST_HOST_PATH:-$HOME/.gerbil}/lib" just test-file "$file" > "$log" 2>&1
      tail -5 "$log"
    done

# One native harness amortizes Gerbil startup and module loading across files.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    files=(t/funflow-tutorial-test.ss t/functional-flow-kernel-test.ss t/functional-flow-kleisli-test.ss t/funflow-job-test.ss t/funflow-profile-test.ss t/core-test.ss t/admission-binding-test.ss t/admission-publication-test.ss t/admission-checked-publication-test.ss t/source-admission-test.ss t/source-observation-test.ss t/path-slots-test.ss t/slot-origin-test.ss t/module-scope-syntax-test.ss t/feature-system*-test.ss t/domain-case*-test.ss t/utilities-functional-test.ss t/composition-roles-test.ss t/poo-clos-*-test.ss t/graph-*-test.ss t/contribution-*-test.ss t/service-publication-fixture-test.ss t/gitea-postgresql-publication-test.ss t/gitea-postgresql-relocation-test.ss t/gitea-json-configuration-test.ss t/module-schema-*-test.ss t/module-option-objects-test.ss t/module-interface-test.ss t/module-graph-test.ss t/module-source-test.ss t/module-authoring-test.ss t/module-scope-link-test.ss t/module-directory-test.ss t/module-explicit-sources-test.ss t/module-source-admission-test.ss t/module-publication-test.ss t/module-selected-graph-test.ss t/module-build-graph-test.ss t/module-configuration-source-test.ss t/module-configuration-build-test.ss t/opentofu-publication-test.ss t/ops-module-publication-test.ss t/ops-functional-test.ss t/ops-process-script-test.ss t/ops-selected-packages-test.ss t/ops-rounds-test.ss t/module-nix-publication-test.ss t/module-json-schema-publication-test.ss t/module-bootstrap-test.ss t/module-selection-test.ss t/module-load-path-test.ss t/module-context-test.ss t/module-loader-backend-test.ss t/module-catalog-test.ss t/module-diagnostics-test.ss t/semantic-module-test.ss t/profile-composition-test.ss t/observability-*-test.ss t/slot-presentation-test.ss)
    files+=(t/module-windows-test.ss)
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gerbil {{ gerbil_test_runtime_options }} test "${files[@]}" 2>&1 | tee "$log"
    if grep -E 'ERROR (CHECK|CASE|HARNESS)|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    for file in "${files[@]}"; do grep -F "MODULE-OK $file" "$log" >/dev/null; done
    grep -F 'HARNESS-OK' "$log" >/dev/null
    grep -x 'OK' "$log" >/dev/null

# Opt-in wall/user/system timing while preserving the same bounded test path.
test-profile:
    time just test

# Real pinned Provider Schema publications and a local Null apply/destroy.
# AWS is rendered and validated without deployment. Uses the bounded native harness.
test-opentofu-admission-execution:
    just test-file t/opentofu-admission-execution-test.ss

# Public AWS ObjectContract layers; no Nix invocation or external effect.
test-aws-contracts:
    just test-file t/aws-module-test.ss

# Real AWS Schema packages, child Context admission and publication; no deployment.
test-aws-context-publication:
    just test-file t/aws-context-publication-test.ss

# Bounded, opt-in CLOS dispatch profiling outside the unit-test harness.
benchmark-dispatch:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-dispatch-benchmark.ss

benchmark-slot:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-slot-benchmark.ss

benchmark-effective-slots:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-effective-slot-benchmark.ss

# Dependent class redefinition includes native C4 preflight and live commit.
benchmark-redefinition:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-redefinition-benchmark.ss

# One Core Lake project; LeanPoo is its immutable dependency.
proofs: proofs-quint proofs-lean

proofs-lean:
    cd proofs/lean && timeout 120s lake build

# Source-level ownership controls; heap fence applies before any imports.
test-module-ownership:
    #!/usr/bin/env bash
    set -euo pipefail
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/module-ownership/run.ss 2>&1 | tee "$log"
    if grep -E 'ERROR (CASE|CHECK|HARNESS)|Heap overflow|Stack overflow' "$log" >/dev/null; then exit 1; fi
    grep -F 'MODULE-OK t/qualification/module-ownership/run.ss' "$log" >/dev/null
    grep -F 'HARNESS-OK module-ownership' "$log" >/dev/null
    grep -x 'OK' "$log" >/dev/null

# Source-only qualification: retain installed external dependencies, remove Core.
test-bootstrap:
    just test-file t/module-build-process-test.ss

# Selected module suites remain native std/test files, executed through Ops.
test-modules:
    just test-file t/testing-script-test.ss
    just test-file t/module-testing-test.ss
    just test-file t/module-testing-isolation-test.ss
    just test-file t/module-testing-compiled-test.ss

# Core-owned provider fixtures and declarative Ops qualification.
# Explicit real-provider artifact gate; the native test streams the binary.
[group('test')]
test-opentofu-aws-binary binary:
    POO_FLOW_AWS_BINARY="{{ binary }}" just test-file t/opentofu-aws-binary-test.ss

# Explicit package-artifact control; no Loader or provider process in admission.
[group('test')]
test-opentofu-provider-artifact artifact:
    POO_FLOW_OPENTOFU_TEST_ARTIFACT="{{ artifact }}" just test-file t/opentofu-provider-artifact-test.ss

# The two arguments must be real Nix schema outputs, not edited manifests.
[group('test')]
test-opentofu-provider-versions parent child:
    POO_FLOW_OPENTOFU_TEST_PARENT_ARTIFACT="{{ parent }}" POO_FLOW_OPENTOFU_TEST_CHILD_ARTIFACT="{{ child }}" just test-file t/opentofu-provider-versions-test.ss

# One real package collection; uses the default heap-fenced native harness.
[group('test')]
test-opentofu-provider-families artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-provider-families-test.ss

[group('test')]
test-opentofu-configuration-families artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-configuration-families-test.ss

[group('test')]
test-opentofu-configuration-discovery artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-configuration-discovery-test.ss

[group('test')]
test-opentofu-indexed-inputs artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-indexed-inputs-test.ss

[group('test')]
test-opentofu-artifact-collection artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-artifact-collection-test.ss

# Project Provider package demand without reading any injected artifact.
[group('test')]
test-opentofu-build-demand output:
    env -u POO_FLOW_OPENTOFU_ARTIFACT POO_FLOW_OPENTOFU_TEST_SELECTION="{{ output }}" just test-file t/opentofu-build-selection-test.ss

# Admit against the real collection produced from the demand projection.
[group('test')]
test-opentofu-selected-artifact artifact:
    POO_FLOW_OPENTOFU_ARTIFACT="{{ artifact }}" just test-file t/opentofu-build-selection-test.ss

# Real Nix handoff from the Core selected graph; no product Loader.
[group('test')]
test-opentofu-selected-graph:
    just test-file t/opentofu-selected-graph-test.ss

# Each round retains the standard heap fence/timeout; raw logs stay outside Git.
[group('test')]
test-opentofu-selected-graph-rounds output rounds="5":
    gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/opentofu/opentofu-rounds.ss --rounds "{{ rounds }}" --output "{{ output }}"

# Locked local flake; package fixtures remain an explicit test input.
[group('test')]
test-nix-flake artifact:
    POO_FLOW_OPENTOFU_FLAKE_ARTIFACT="{{ artifact }}" POO_FLOW_NIX_TEST_TOOLS="$(nix-instantiate --eval --strict --json --expr 'with import <nixpkgs> {}; { shell = toString bash; tools = toString coreutils; }')" just test-file t/nix-flake-source-test.ss

# Same serial observations, plus locked flake Sources; no product Loader.
[group('test')]
test-opentofu-nix-rounds output artifact rounds="5":
    gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/opentofu/opentofu-rounds.ss --rounds "{{ rounds }}" --output "{{ output }}" --flake-artifact "{{ artifact }}"

# Test-only explicit package setup creates the lock; selected runtime is read-only.
[group('test')]
prepare-opentofu-flake output package_ref:
    python3 t/qualification/opentofu/prepare-opentofu-flake.py --output "{{ output }}" --package-ref "{{ package_ref }}"

[group('test')]
test-opentofu-selected-flake source:
    POO_FLOW_OPENTOFU_GRAPH_FLAKE="{{ source }}" just test-file t/opentofu-selected-graph-test.ss

# Demand comes from final Config; the prepared flake/lock is read-only at runtime.
[group('test')]
test-opentofu-selected-flake-rounds output source rounds="3":
    gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/opentofu/opentofu-rounds.ss --rounds "{{ rounds }}" --output "{{ output }}" --selected-flake "{{ source }}"

# Native operational CLI discovery; no test/build process is started by --help.
[group('test')]
ops-help:
    gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/opentofu/opentofu-rounds.ss --help

# OpenTofu uses the same default native entry as every focused Scheme test.
[group('test')]
test-opentofu path="t/opentofu-schema-test.ss":
    just test-file "{{ path }}"

# All maintained finite models are Quint; receipts remain local artifacts.
proofs-quint receipt="/private/tmp/core-quint-proof.ss":
    python3 proofs/quint/check.py --receipt "{{ receipt }}"

# Tool/backend bootstrap is preparation, never an accepted proof receipt.
prepare-quint:
    npm ci --prefix proofs/quint --no-audit --no-fund
    python3 proofs/quint/prepare.py
