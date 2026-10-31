# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# Qualification-only source dispatcher, built outside the checkout.
test-source-tail-gateway directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_SOURCE_TAIL_ROOT="{{ directory }}"
    export CORE_SOURCE_TAIL_CORE="$(pwd)/"
    test ! -e "$CORE_SOURCE_TAIL_ROOT/source"
    mkdir -p "$CORE_SOURCE_TAIL_ROOT"
    GERBIL_LOADPATH="$CORE_SOURCE_TAIL_ROOT/source:$(pwd):${GERBIL_TEST_HOST_PATH:-${GERBIL_PATH:-$(pwd)/.gerbil}}/lib" env -u SDKROOT timeout --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi {{ gerbil_test_runtime_options }} t/qualification/mop-state/compile-tail-gateway.ss
    # The launcher imports ./init.ss. It must select the SAME snapshot whose
    # libraries were compiled above, not combine live declarations with clones.
    GERBIL_LOADPATH="$CORE_SOURCE_TAIL_ROOT/lib:$CORE_SOURCE_TAIL_ROOT/source:$(pwd):${GERBIL_TEST_HOST_PATH:-${GERBIL_PATH:-$(pwd)/.gerbil}}/lib" just --justfile "$PWD/Justfile" --working-directory "$CORE_SOURCE_TAIL_ROOT/source/yuanxu" test-file "$CORE_SOURCE_TAIL_ROOT/source/yuanxu/t/source-admission-gateway-test.ss"

# Matched dispatcher policies in an already compiled, captured Core package.
test-source-tail-policy directory:
    #!/usr/bin/env bash
    set -euo pipefail
    export CORE_SOURCE_TAIL_POLICY="${CORE_SOURCE_TAIL_POLICY:-segment}"
    export CORE_SOURCE_TAIL_ROOT="{{ directory }}"
    export CORE_SOURCE_TAIL_CORE="$(pwd)/"
    test -f "$CORE_SOURCE_TAIL_ROOT/lib/yuanxu/module-system/source/admission.o1"
    export GERBIL_LOADPATH="$CORE_SOURCE_TAIL_ROOT/lib:$CORE_SOURCE_TAIL_ROOT/source:$(pwd):${GERBIL_TEST_HOST_PATH:-${GERBIL_PATH:-$(pwd)/.gerbil}}/lib"
    env -u SDKROOT timeout --foreground --signal=TERM --kill-after=5s 120s gerbil {{ gerbil_test_runtime_options }} env gxi {{ gerbil_test_runtime_options }} t/qualification/mop-state/refine-tail-policy.ss
    if [[ "$CORE_SOURCE_TAIL_POLICY" == unrestricted ]]; then
        just test-file t/source-admission-closed-tail-test.ss
    else
        just test-file t/source-admission-gateway-test.ss
    fi

test-mop-store-boundary directory:
    just compile-mop-store-boundary "{{ directory }}"
    just verify-mop-store-boundary-runtime "{{ directory }}"

test-source-loader-authority directory:
    CORE_STORE_ROOT="{{ directory }}" just test-file t/source-loader-authority-test.ss

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

test-slot-read-costs directory file label:
    #!/usr/bin/env bash
    set -euo pipefail
    YUANXU_READ_COST_LABEL="{{ label }}" GERBIL_LOADPATH="{{ directory }}/lib:{{ directory }}/source:$(pwd):$HOME/.gerbil/lib" just test-file "{{ file }}"

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
