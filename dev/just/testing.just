# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# Prerequisites and Core must already be built in this explicit environment.
# Core owns the independent production source-view adapter gate.
test-selected-package-builds directory:
    GERBIL_PATH="{{ directory }}" GERBIL_LOADPATH="{{ directory }}/lib" just test-file t/selected-source-view-lifecycle-test.ss

# Real 1000-directory source corpus, one Profile root and its required provider.
test-thousand-package-builds directory:
    GERBIL_PATH="{{ directory }}" GERBIL_LOADPATH="{{ directory }}/lib" just test-file t/thousand-package-downstream-test.ss

# One cold business .get includes first declaration admission and reached scopes.
# Keep the existing Case watchdog/heap fence; report elapsed time, not a budget.
measure-thousand-business-eval directory:
    GERBIL_PATH="{{ directory }}" GERBIL_LOADPATH="{{ directory }}/lib" just test-file t/module-business-eval-once-1000-test.ss

# Independent diagnostic probes, with native CPU/wall accounting per stage.
measure-thousand-eval-stages directory:
    GERBIL_PATH="{{ directory }}" GERBIL_LOADPATH="{{ directory }}/lib" just test-file t/module-runtime-attribution-1000-test.ss stages

# Convenience alias only. Gerbil owns loading, discovery, fixtures and status.
test-file path observe="false":
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}"
    export GERBIL_LOADPATH="${GERBIL_LOADPATH:+$GERBIL_LOADPATH:}$GERBIL_PATH/lib:$PWD"
    runtime_options="{{ gerbil_test_runtime_options }}"
    case "{{ path }}" in
      *-10000-test.ss) runtime_options="-:max-heap=4G,debug={{ gerbil_test_debug }}" ;;
    esac
    options=()
    case "{{ observe }}" in
      false) ;;
      true) options=(-D yuanxu-module-test-observation) ;;
      trace) options=(-D yuanxu-module-test-observation,yuanxu-module-test-trace) ;;
      stages) options=(-D yuanxu-module-test-stage-accounting) ;;
      *) echo 'observe must be false, true, trace, or stages' >&2; exit 64 ;;
    esac
    deadline=600s
    case "{{ path }}" in
      *module-declaration-10000-test.ss|*module-runtime-selection-10000-test.ss) deadline=680s ;;
    esac
    env -u SDKROOT timeout --signal=TERM --kill-after=5s "$deadline" gerbil "$runtime_options" test ${options[@]+"${options[@]}"} "{{ path }}"

# Fault injection uses fresh native module overlays and the same test-file gates.
# Compilation is preparation; each test retains its existing heap/watchdog fence.
test-build-input-context-mutations artifacts:
    RUNNER_TEMP="{{ artifacts }}" just test-file t/build-input-mutations-test.ss

test-build-publication directory file="t/build-artifact-publication-test.ss":
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="{{ directory }}/lib:$(pwd)${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    just test-file "{{ file }}"

# Independent snapshot consumer; uses the same pre-import heap fence as tests.
# Independent persistent-head consumer, bounded before any Scheme import.
persistent-head-worker path operation argument="":
    @env -u SDKROOT timeout --signal=TERM --kill-after=5s 30s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/persistent-head-worker.ss "{{ path }}" "{{ operation }}" "{{ argument }}"

# Focused alias only; complete CI coverage is the checked domain matrix.
test path:
    just test-file "{{ path }}"

# Opt-in timing of that same official command, without an aggregate rerun.
test-profile path:
    time just test-file "{{ path }}"

# Real pinned Provider Schema publications and a local Null apply/destroy.
# AWS is rendered and validated without deployment. Uses the bounded runtime harness.

# Public AWS ObjectContract layers; no Nix invocation or external effect.

# Real AWS Schema packages, child Context admission and publication; no deployment.

# Bounded, opt-in CLOS dispatch profiling outside the unit-test harness.
benchmark-dispatch:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-dispatch-benchmark.ss

benchmark-slot:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-slot-benchmark.ss

benchmark-effective-slots:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-effective-slot-benchmark.ss

# Dependent class redefinition includes runtime C4 preflight and live commit.
benchmark-redefinition:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi t/poo-clos-redefinition-benchmark.ss

# Source-level ownership controls; heap fence applies before any imports.
test-module-ownership:
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} test t/qualification/module-ownership/run.ss

# Source-only qualification: retain installed external dependencies, remove Core.
test-bootstrap:
    just test-file t/module-build-process-test.ss

# Selected module suites remain ordinary std/test files.
test-modules:
    just test-file t/module-test-preparation-test.ss
    just test-file t/testing-script-test.ss
    just test-file t/module-testing-test.ss
    just test-file t/module-testing-isolation-test.ss
    just test-file t/module-testing-compiled-test.ss
    just test-selected-modules

# A complete published module test group is an external integration phase,
# never a Case inside the test which verifies discovery/projection mechanics.
test-selected-modules:
    #!/usr/bin/env bash
    set -euo pipefail
    export GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}"
    files=()
    selected=$(gxi {{ gerbil_test_runtime_options }} -e '(import (only-in "./dev/ci-inventory.ss" main))' -e '(main "--published")')
    test -n "$selected"
    while IFS= read -r file; do files+=("$file"); done <<< "$selected"
    test "${#files[@]}" -gt 0
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 600s gerbil {{ gerbil_test_runtime_options }} test "${files[@]}"

verify-mop-store-boundary-runtime directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_STORE_ROOT="{{ directory }}"
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="$CORE_STORE_ROOT/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    just test-file t/artifact-closure-test.ss
    just test-file t/qualification/mop-state/store-boundary-driver.ss
    shasum -a 256 -c "$CORE_STORE_ROOT/callback-artifacts.sha256"
    shasum -a 256 -c "$CORE_STORE_ROOT/inputs.sha256"
    shasum -a 256 -c "$CORE_STORE_ROOT/gerbil-inputs.sha256"

test-artifact-authority directory:
    CORE_STORE_ROOT="{{ directory }}" just test-file t/artifact-authority-test.ss

test-issuer-projection directory:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ directory }}"
    trace="$(cd "{{ directory }}" && pwd)/runtime-trace.json"
    CORE_ISSUER_TRACE="$trace" just test-file t/issuer-projection-test.ss
    just check-issuer-projection "$trace"

# The root prelude keeps its unique public compiler identity.
test-yuanxu-prelude:
    just test-file t/prelude-test.ss

# Metadata-only native namespace benchmark. Supply the captured pre-change
# compiled library identity for a reference process, or candidate for the cohort.
benchmark-namespace-branches root implementation samples="3":
    #!/usr/bin/env bash
    set -euo pipefail
    time_options=(-v)
    if [[ "$(uname -s)" == Darwin ]]; then time_options=(-l); fi
    /usr/bin/time "${time_options[@]}" env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/selected-packages/namespace-branch-worker.ss "{{ root }}" "{{ implementation }}" "{{ samples }}"

# Both captured source cohorts use this same optimized native compiler entry.
compile-namespace-branches reference candidate:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gxc {{ gerbil_test_runtime_options }} -O "{{ reference }}" "{{ candidate }}"

# Match gxtest's non-recursive `test t` discovery exactly: direct children
# ending in -test.ss, in runtime lexical order. Each existing test-file gate
# gets the original CI heap limit; no suite or assertion is excluded.
test-files group="all":
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} -e '(import (only-in "./dev/ci-inventory.ss" main))' -e '(main "--list" "{{ group }}")'

# CI consumes this exact, checked domain partition; it never reruns `all`.
test-ci-groups:
    @GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} -e '(import (only-in "./dev/ci-inventory.ss" main))' -e '(main "--matrix")'

# Each file retains a fresh official Gerbil process, including cold-load tests.
# This alias supplies arguments only; no Harness or verdict parser exists here.
test-directory group:
    #!/usr/bin/env bash
    set -euo pipefail
    selected=$(just test-files "{{ group }}")
    test -n "$selected"
    failed=0
    while IFS= read -r file; do
        if ! just test-file "$file"; then failed=1; fi
    done <<< "$selected"
    exit "$failed"
