# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# gxtest owns package setup. Keep the actual test VM in the watchdog group.
test-file path observe="false": build-test-fixtures (_test-file path observe)

# The official Gerbil owns compilation before the native Case process starts.
# Three versioned compiler Fixtures qualify support reuse/options/admission.
# The fourth package consumes init's existing module qualification declaration;
# source mutation and product tampering remain in their original Scheme Cases.
build-test-fixtures:
    #!/usr/bin/env bash
    set -euo pipefail
    export GAMBOPT="${GAMBOPT:+$GAMBOPT,}max-heap={{ gerbil_test_max_heap }},debug={{ gerbil_test_debug }}"
    for package in native-shared native-options native-preparation native-module-support; do
        prepared_at=$SECONDS
        # Relocated qualification must build its own source epoch, not the
        # checkout containing the Justfile used to launch that snapshot.
        (cd "$PWD/t/qualification/$package" && timeout --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} build)
        printf 'test-preparation phase=complete package=%s elapsed-s=%s\n' "$package" "$((SECONDS - prepared_at))"
    done

[private]
_test-file path observe="false":
    #!/usr/bin/env bash
    set -euo pipefail
    # Native test processes retain their existing individual deadlines.
    # Sequential fixture preparation has its own bounded native invocations.
    budget=180
    # This existing Suite formerly ran as a 60-second nested InputChecks
    # Script. Native discovery now owns it directly, under the SAME limit.
    case "{{ path }}" in
      t/module-build-source-package-test.ss|"$PWD/t/module-build-source-package-test.ss") budget=60 ;;
    esac
    # Native Make backends inherit the same standard Gambit envelope as this
    # parent. The CLI options below still fence the VM before any import.
    export GAMBOPT="${GAMBOPT:+$GAMBOPT,}max-heap={{ gerbil_test_max_heap }},debug={{ gerbil_test_debug }}"
    export GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}"
    if [[ "${PATH%%:*}" != "$GERBIL_PATH/bin" ]]; then export PATH="$GERBIL_PATH/bin:$PATH"; fi
    test_lib="$GERBIL_PATH/test-lib"
    if [[ "{{ observe }}" != false ]]; then printf 'test-entry phase=context elapsed-s=%s\n' "$SECONDS"; fi
    # init and tests belong to the selected working directory, including an
    # explicitly relocated snapshot; the Justfile's location is not authority.
    # Preserve explicit native overlays before the host library fallback.
    # The real source package root replaces the removed nested t/gerbil.pkg.
    GERBIL_LOADPATH="$test_lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:${GERBIL_PATH:-$PWD/.gerbil}/lib:$PWD" env -u SDKROOT timeout --signal=TERM --kill-after=5s "${budget}s" gxi {{ gerbil_test_runtime_options }} t/qualification/testing/run.ss "{{ path }}" "{{ gerbil_test_runtime_options }}" "$budget" "{{ observe }}"

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

# Use the same complete discovered inventory as CI. Keep each original native
# worker's heap/deadline and the separate published-module integration phase.
test:
    just test-directory all
    just test-selected-modules

# Opt-in wall/user/system timing while preserving the same bounded test path.
test-profile:
    time just test

# Real pinned Provider Schema publications and a local Null apply/destroy.
# AWS is rendered and validated without deployment. Uses the bounded native harness.

# Public AWS ObjectContract layers; no Nix invocation or external effect.

# Real AWS Schema packages, child Context admission and publication; no deployment.

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

# Source-level ownership controls; heap fence applies before any imports.
test-module-ownership:
    timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/testing/run.ss t/qualification/module-ownership/run.ss "{{ gerbil_test_runtime_options }}" 120 false "HARNESS-OK module-ownership 21 suites"

# Source-only qualification: retain installed external dependencies, remove Core.
test-bootstrap:
    just test-file t/module-build-process-test.ss false test-file t/module-build-source-package-test.ss false

# Selected module suites remain native std/test files, executed through Ops.
test-modules:
    just test-file t/module-test-preparation-test.ss
    just test-file t/testing-script-test.ss
    just test-file t/module-testing-test.ss
    just test-file t/module-testing-isolation-test.ss
    just test-file t/module-testing-compiled-test.ss
    just test-selected-modules

# A complete published module test group is an external integration phase,
# never a Case inside the test which verifies discovery/projection mechanics.
test-selected-modules: (_test-file "--selected-modules")

verify-mop-store-boundary-runtime directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_STORE_ROOT="{{ directory }}"
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="$CORE_STORE_ROOT/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    just test-file t/artifact-closure-test.ss
    just test-file t/mop-store-boundary-driver-test.ss
    shasum -a 256 -c "$CORE_STORE_ROOT/callback-artifacts.sha256"
    shasum -a 256 -c "$CORE_STORE_ROOT/inputs.sha256"
    shasum -a 256 -c "$CORE_STORE_ROOT/sdk-inputs.sha256"

test-artifact-authority directory:
    CORE_STORE_ROOT="{{ directory }}" just test-file t/artifact-authority-test.ss

test-issuer-projection directory:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ directory }}"
    trace="$(cd "{{ directory }}" && pwd)/native-trace.json"
    CORE_ISSUER_TRACE="$trace" just test-file t/issuer-projection-test.ss
    just check-issuer-projection "$trace"

# The root prelude keeps its unique public compiler identity.
test-yuanxu-prelude:
    just test-file t/prelude-test.ss

# Match gxtest's non-recursive `test t` discovery exactly: direct children
# ending in -test.ss, in native lexical order. Each existing test-file gate
# gets the original CI heap limit; no suite or assertion is excluded.
test-files group="all":
    #!/usr/bin/env bash
    set -euo pipefail
    export LC_ALL=C
    case "{{ group }}" in
      all|bootstrap|modules|scale|contracts|objects|scenarios|runtime) ;;
      *) echo 'unknown test group' >&2; exit 64 ;;
    esac
    shopt -s nullglob
    for file in t/*-test.ss; do
      case "$file" in
        t/package-*|t/prelude-*|t/core-build-*|t/module-build-*|t/module-bootstrap-*|t/runtime-publication-identity-*) owner=bootstrap ;;
        t/module-declaration-1000-test.ss|t/module-declaration-10000-test.ss|t/module-declaration-retention-test.ss|t/module-loading-scale-test.ss) owner=scale ;;
        t/module-*|t/feature-system-*) owner=modules ;;
        t/json-schema-*|t/source-*|t/contract-*|t/admission-*|t/contribution-*|t/configuration-*) owner=contracts ;;
        t/poo-*|t/object-*|t/issued-*|t/path-*|t/evidence-*|t/issuer-*) owner=objects ;;
        t/aws-*|t/gitea-*|t/nix-*|t/ops-*) owner=scenarios ;;
        *) owner=runtime ;;
      esac
      if [[ "{{ group }}" == all || "{{ group }}" == "$owner" ]]; then printf '%s\n' "$file"; fi
    done

# Supply the existing compilation fixture before invoking its std/test facade.
# These suites inspect issued AOT callbacks, not interpreted substitutes.
test-discovered-file path: build-test-fixtures (_test-discovered-file path)

[private]
_test-discovered-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ path }}" in
      t/artifact-closure-test.ss|t/mop-store-boundary-test.ss|t/mop-store-boundary-driver-test.ss)
        fixture=$(mktemp -d)
        trap 'rm -rf "$fixture"' EXIT
        just compile-mop-store-boundary "$fixture"
        if [[ "{{ path }}" == t/artifact-closure-test.ss ]]; then
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just _test-file "{{ path }}"
        else
          printf 'AOT-SUITE %s facade=t/mop-store-boundary-driver-test.ss\n' "{{ path }}"
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just _test-file t/mop-store-boundary-driver-test.ss
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
        CORE_STORE_ROOT="$fixture" just _test-file "{{ path }}"
        ;;
      *) just _test-file "{{ path }}" ;;
    esac

test-directory group="all": build-test-fixtures
    #!/usr/bin/env bash
    set -euo pipefail
    export LC_ALL=C
    manifest=$(just test-files "{{ group }}")
    files=()
    while IFS= read -r file; do [[ -z "$file" ]] || files+=("$file"); done <<< "$manifest"
    test "${#files[@]}" -gt 0
    printf '[yuanxu-testing] phase=test-directory-manifest fileCount=%s\n' "${#files[@]}"
    printf '%s\n' "${files[@]}"
    failed=()
    for file in "${files[@]}"; do
      # Match the complete test entry: prepare shared support once, then keep
      # every original file in its independently heap-fenced native worker.
      if ! just _test-discovered-file "$file"; then
        failed+=("$file")
      fi
    done
    if (( ${#failed[@]} )); then
      printf 'FAILED-TEST %s\n' "${failed[@]}" >&2
      exit 1
    fi
    printf '[yuanxu-testing] phase=test-directory-complete fileCount=%s\n' "${#files[@]}"
