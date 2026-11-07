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

# Independent diagnostic probes, with wall-only operation instrumentation.
measure-thousand-eval-stages directory:
    GERBIL_PATH="{{ directory }}" GERBIL_LOADPATH="{{ directory }}/lib" just test-file t/module-runtime-attribution-1000-test.ss

test-file path observe="false":
    #!/usr/bin/env bash
    set -euo pipefail
    launcher=(gxi)
    if [[ -z "${GERBIL_PATH:-}" ]]; then
        launcher=(gerbil {{ gerbil_test_runtime_options }} env gxi)
    elif [[ "${PATH%%:*}" != "$GERBIL_PATH/bin" ]]; then
        export PATH="$GERBIL_PATH/bin:$PATH"
    fi
    # Do not boot another Gerbil instance just
    # to print the same fixed value and its runtime package directory.
    budget=600
    test_lib="${GERBIL_PATH:-$PWD/.gerbil}/test-lib"
    # Tests belong to the selected working directory, including an
    # explicitly relocated snapshot; the Justfile's location is not authority.
    # Preserve explicit runtime overlays before the host library fallback.
    # The real source package root replaces the removed nested t/gerbil.pkg.
    options=()
    case "{{ observe }}" in
      false) ;;
      true) options=(-D yuanxu-module-test-observation) ;;
      trace) options=(-D yuanxu-module-test-observation,yuanxu-module-test-trace) ;;
      *) echo 'observe must be false, true, or trace' >&2; exit 64 ;;
    esac
    GERBIL_LOADPATH="$test_lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:${GERBIL_PATH:-$PWD/.gerbil}/lib:$PWD" env -u SDKROOT timeout --signal=TERM --kill-after=5s "${budget}s" "${launcher[@]}" {{ gerbil_test_runtime_options }} dev/test-file.ss ${options[@]+"${options[@]}"} "{{ path }}"

# Fault injection uses fresh native module overlays and the same test-file gates.
# Compilation is preparation; each test retains its existing heap/watchdog fence.
test-build-input-context-mutations artifacts:
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" {{ gerbil_compiler_environment }} gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss --mutate-build-input "{{ artifacts }}" '{{ gerbil_test_runtime_options }}'

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

# Local and CI runs share the discovered platform inventory. The nested
# allocation diagnostic and published Module suites remain separate invocations.
test: test-platform
    just test-file t/qualification/observability/raw-allocation-test.ss
    just test-selected-modules

# Opt-in wall/user/system timing while preserving the same bounded test path.
test-profile:
    time just test

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
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} dev/test-file.ss t/qualification/module-ownership/run.ss

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
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 600s gerbil {{ gerbil_test_runtime_options }} env gxi {{ gerbil_test_runtime_options }} -e '(import :clan/poo/object (only-in "./init.ss" yuanxu.init.exports) (rename-in (only-in "./dev/test-file.ss" main) (main test-main)))' -e '(def tests (.get yuanxu.init.exports tests))' -e '(def files (.get tests spec))' -e '(unless (pair? files) (error "selected module tests are empty"))' -e '(dynamic-wind (.get tests admit-current) (lambda () (apply test-main files)) (.get tests admit-current))'

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
    shasum -a 256 -c "$CORE_STORE_ROOT/sdk-inputs.sha256"

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
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss --list "{{ group }}"

# Supply the existing compilation fixture before invoking its std/test facade.
# These suites inspect issued AOT callbacks, not interpreted substitutes.
test-discovered-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ path }}" in
      t/artifact-closure-test.ss|t/mop-store-boundary-test.ss)
        fixture=$(mktemp -d)
        trap 'rm -rf "$fixture"' EXIT
        just compile-mop-store-boundary "$fixture"
        if [[ "{{ path }}" == t/artifact-closure-test.ss ]]; then
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just test-file "{{ path }}"
        else
          printf 'AOT-SUITE %s facade=t/qualification/mop-state/store-boundary-driver.ss\n' "{{ path }}"
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just test-file t/qualification/mop-state/store-boundary-driver.ss
        fi
        shasum -a 256 -c "$fixture/callback-artifacts.sha256"
        shasum -a 256 -c "$fixture/inputs.sha256"
        shasum -a 256 -c "$fixture/sdk-inputs.sha256"
        ;;
      t/source-admission-gateway-test.ss)
        fixture=$(mktemp -d)
        trap 'rm -rf "$fixture"' EXIT
        just test-source-tail-gateway "$fixture"
        ;;
      t/artifact-authority-test.ss|t/source-loader-authority-test.ss)
        fixture=$(mktemp -d)
        trap 'rm -rf "$fixture"' EXIT
        CORE_STORE_ROOT="$fixture" just test-file "{{ path }}"
        ;;
      *) just test-file "{{ path }}" ;;
    esac

test-directory group="all":
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss "{{ group }}" '{{ gerbil_test_runtime_options }}'

test-platform:
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss --platform '{{ gerbil_test_runtime_options }}'

test-report-audit directory group="all":
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss --audit "{{ directory }}" "{{ group }}"

test-report-compare linux macos group="all":
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} dev/test-directory-report.ss --compare "{{ linux }}" "{{ macos }}" "{{ group }}"
