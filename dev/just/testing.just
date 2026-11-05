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
    GERBIL_LOADPATH="$test_lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:${GERBIL_PATH:-$PWD/.gerbil}/lib:$PWD" env -u SDKROOT timeout --signal=TERM --kill-after=5s "${budget}s" "${launcher[@]}" {{ gerbil_test_runtime_options }} dev/test-file.ss "${options[@]}" "{{ path }}"

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

# Give each file its existing bounded runtime harness and compiler context.
# Repository-wide imports retain mutable fixtures and source-reader epochs.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    files=(t/qualification/observability/raw-allocation-test.ss t/module-case-profile-test.ss t/module-test-executor-import-test.ss t/funflow-function-types-test.ss t/contract-function-composition-test.ss t/functional-flow-kernel-test.ss t/functional-flow-kleisli-test.ss t/core-test.ss t/admission-binding-test.ss t/admission-publication-test.ss t/admission-checked-publication-test.ss t/source-admission-test.ss t/contract-analysis-test.ss t/root-child-admission-test.ss t/root-child-effect-test.ss t/source-observation-test.ss t/path-slots-test.ss t/slot-origin-test.ss t/module-scope-syntax-test.ss t/feature-system*-test.ss t/domain-case*-test.ss t/utilities-functional-test.ss t/composition-roles-test.ss t/poo-clos-*-test.ss t/graph-*-test.ss t/contribution-*-test.ss t/service-publication-fixture-test.ss t/gitea-postgresql-publication-test.ss t/gitea-postgresql-relocation-test.ss t/gitea-json-configuration-test.ss t/module-schema-*-test.ss t/module-option-objects-test.ss t/module-interface-test.ss t/module-graph-test.ss t/module-source-test.ss t/module-authoring-test.ss t/module-scope-link-test.ss t/module-directory-test.ss t/module-explicit-sources-test.ss t/module-source-admission-test.ss t/module-declaration-value-test.ss t/module-deferred-projection-test.ss t/module-role-context-test.ss t/module-publication-test.ss t/module-selected-graph-test.ss t/module-build-graph-test.ss t/module-build-artifact-clean-test.ss t/module-configuration-source-test.ss t/module-configuration-build-test.ss t/ops-module-publication-test.ss t/ops-functional-test.ss t/ops-process-script-test.ss t/module-json-schema-publication-test.ss t/module-bootstrap-test.ss t/module-selection-test.ss t/module-load-path-test.ss t/module-context-test.ss t/module-loader-backend-test.ss t/module-loader-publication-test.ss t/module-catalog-test.ss t/module-diagnostics-test.ss t/semantic-module-test.ss t/profile-composition-test.ss t/observability-*-test.ss t/slot-presentation-test.ss)
    files+=(t/namespace-projection-test.ss t/namespace-leaf-expression-test.ss t/module-source-package-resolution-test.ss t/package-install-test.ss t/module-session-metadata-index-test.ss t/module-windows-test.ss t/module-testing-isolation-test.ss t/module-test-preparation-test.ss)
    for file in "${files[@]}"; do just test-file "$file"; done
    just test-selected-modules
    echo "[yuanxu-testing] phase=all-files-complete fileCount=${#files[@]}"

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
test-discovered-file path:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ path }}" in
      t/artifact-closure-test.ss|t/mop-store-boundary-test.ss|t/mop-store-boundary-driver-test.ss)
        fixture=$(mktemp -d)
        trap 'rm -rf "$fixture"' EXIT
        just compile-mop-store-boundary "$fixture"
        if [[ "{{ path }}" == t/artifact-closure-test.ss ]]; then
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just test-file "{{ path }}"
        else
          printf 'AOT-SUITE %s facade=t/mop-store-boundary-driver-test.ss\n' "{{ path }}"
          CORE_STORE_ROOT="$fixture" GERBIL_LOADPATH="$fixture/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}" just test-file t/mop-store-boundary-driver-test.ss
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
      if ! just test-discovered-file "$file"; then
        failed+=("$file")
      fi
    done
    if (( ${#failed[@]} )); then
      printf 'FAILED-TEST %s\n' "${failed[@]}" >&2
      exit 1
    fi
    printf '[yuanxu-testing] phase=test-directory-complete fileCount=%s\n' "${#files[@]}"
