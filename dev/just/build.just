# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

build:
    GERBIL_BUILD_VERBOSE=1 env -u SDKROOT gerbil build

# Keep optimized compiler metadata and its implementation in the same cohort.
# A non-optimized overwrite can otherwise leave stale .ssxi entry references.
compile-build-projection:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxc -O module-system/building/source-closure.ss

# Opt-in read-cost gates; retain the same pre-import heap fence and watchdog.
compile-slot-read-costs directory file:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_REPLAY_ROOT="{{ directory }}"
    export CORE_REPLAY_CORE="${CORE_REPLAY_INPUT_CORE:-$(pwd)/}"
    export CORE_REPLAY_COMPILE_FILE="{{ file }}"
    (cd "$CORE_REPLAY_ROOT/source/clan/poo"; rg --files -0 -g '*.ss' -g '*.scm' | sort -z | xargs -0 shasum -a 256) > "$CORE_REPLAY_ROOT/dependency-source.sha256"
    log="$(mktemp "$CORE_REPLAY_ROOT/cost-compile-XXXXXX.log")"
    GERBIL_LOADPATH="$CORE_REPLAY_ROOT/lib:$CORE_REPLAY_ROOT/source:$(pwd):$HOME/.gerbil/lib" env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gxi {{ gerbil_test_runtime_options }} t/qualification/slot-read-replay/compile.ss > "$log" 2>&1

# Process-local compiler lowering; production SDK/source untouched.
compile-mop-store-boundary directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_STORE_ROOT="{{ directory }}"
    mkdir -p "$CORE_STORE_ROOT/lib"
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="$CORE_STORE_ROOT/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    shasum -a 256 t/qualification/mop-state/compile-store-boundary.ss t/qualification/mop-state/store-policy.ss t/qualification/mop-state/unlowered-store.ss t/qualification/mop-state/precompiled-stores.ss t/mop-store-boundary-test.ss t/mop-store-boundary-driver-test.ss "$GERBIL_PATH/lib/clan/poo/object~0.scm" > "$CORE_STORE_ROOT/inputs.sha256"
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/mop-state/compile-store-boundary.ss
    just build-mop-store-boundary-runtime "$CORE_STORE_ROOT"

build-mop-store-boundary-runtime directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_STORE_ROOT="{{ directory }}"
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="$CORE_STORE_ROOT/lib${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    shasum -a 256 -c "$CORE_STORE_ROOT/inputs.sha256"
    shasum -a 256 "$CORE_STORE_ROOT/lib/yuanxu/t/qualification/mop-state/precompiled-stores~0.scm" "$CORE_STORE_ROOT/lib/yuanxu/t/qualification/mop-state/precompiled-stores~0.o1" "$CORE_STORE_ROOT/lib/yuanxu/t/qualification/mop-state/unlowered-store~0.scm" "$CORE_STORE_ROOT/lib/yuanxu/t/qualification/mop-state/unlowered-store~0.o1" > "$CORE_STORE_ROOT/callback-artifacts.sha256"
    sdk_home="$(cat "$CORE_STORE_ROOT/sdk-home")"
    export GAMBOPT="${GAMBOPT:+$GAMBOPT,}~~=$sdk_home,~~bin=$sdk_home/bin,~~lib=$sdk_home/lib"
    gsc_features=()
    if [[ "$(cat "$CORE_STORE_ROOT/sdk-smp")" == true ]]; then
        gsc_features=(-e '(define-cond-expand-feature|enable-smp|)')
    fi
    shasum -a 256 "$sdk_home/lib/gerbil/runtime/mop~0.scm" "$sdk_home/lib/_gambit#.scm" "$sdk_home/lib/_thread#.scm" "$sdk_home/include/gambit.h" > "$CORE_STORE_ROOT/sdk-inputs.sha256"
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s "$sdk_home/bin/gsc" {{ gerbil_test_runtime_options }} -dynamic -o "$CORE_STORE_ROOT/store-runtime.o1" "${gsc_features[@]}" "$CORE_STORE_ROOT/store-runtime.scm"
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s "$sdk_home/bin/gsc" {{ gerbil_test_runtime_options }} -dynamic -o "$CORE_STORE_ROOT/loader-runtime.o1" "${gsc_features[@]}" "$CORE_STORE_ROOT/loader-runtime.scm"
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/mop-state/seal-artifact-closure.ss

compile-build-publication directory:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ directory }}/lib"
    export CORE_BUILD_PUBLICATION_LIB="{{ directory }}/lib"
    export GERBIL_PATH="${GERBIL_PATH:-$(pwd)/.gerbil}"
    export GERBIL_LOADPATH="$CORE_BUILD_PUBLICATION_LIB:$(pwd)${GERBIL_LOADPATH:+:$GERBIL_LOADPATH}:$GERBIL_PATH/lib"
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/compile.ss

# Reuse an owned, previously qualified Core closure; compile changed source units.
# This is a separate gate, not a pass of the monolithic 47-unit compile deadline.
compile-build-publication-delta directory baseline:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{ baseline }}/core-sources.sha256"
    test ! -e "{{ directory }}"
    mkdir -p "{{ directory }}/lib"
    cp -R "{{ baseline }}/lib/." "{{ directory }}/lib/"
    export CORE_BUILD_PUBLICATION_BASE="{{ baseline }}"
    just compile-build-publication "{{ directory }}"

# Parent owns stdin; worker receives retained Core issuance, not a sidecar.
build-publication-worker root lib identity mode record:
    #!/usr/bin/env bash
    set -euo pipefail
    launcher=(gxi)
    if [[ -z "${GERBIL_PATH:-}" ]]; then launcher=(gerbil env gxi); fi
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s "${launcher[@]}" {{ gerbil_test_runtime_options }} t/qualification/build-publication/worker.ss "{{ root }}" "{{ lib }}" "{{ identity }}" "{{ mode }}" "{{ record }}"

build-store-producer root:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/store-producer.ss "{{ root }}"

build-approved-producer root:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/approved-producer.ss "{{ root }}"

build-approved-worker root mode:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/worker.ss "{{ root }}" "approved-{{ mode }}"

build-store-worker root lib identity mode record selected candidate:
    env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil env gxi {{ gerbil_test_runtime_options }} t/qualification/build-publication/worker.ss "{{ root }}" "{{ lib }}" "{{ identity }}" "{{ mode }}" "{{ record }}" "{{ selected }}" "{{ candidate }}"
