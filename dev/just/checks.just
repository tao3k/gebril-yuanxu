# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# Compiled/public sources must use the current Core and Feature namespaces.
check-package-namespace: check-package-independence
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    rg -n 'AgenticAILab|agentic[-]ai[-]lab-core|agentic[-]ai[-]lab-|:co[r]e/|:agentic[-]ai[-]lab/|package: core|:tao3k/yuanxu/(feature[-]system|module-system/feature[-]system|module-system/source/feature[-]scopes)/?' --glob '*.ss' --glob '*.scm' --glob '*.py' --glob '*.nix' --glob '*.yml' --glob '*.yaml' --glob '*.toml' --glob '*.lean' --glob '*.qnt' --glob '*.sh' --glob 'gerbil.pkg' . || status=$?
    case "$status" in
      0) echo 'retired Yuanxu namespace found' >&2; exit 1 ;;
      1) echo 'YUANXU-NAMESPACE-OK' ;;
      *) exit "$status" ;;
    esac

# Downstream products own their integration tests and source bindings.
check-package-independence:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    # Include untracked source files; a new fixture must not bypass this gate.
    rg -n 'agentic[-]ai[-]lab|lab[-]root|YUANXU_(LAB_SOURCE|SELECTED_RUNTIME|THOUSAND_SOURCE)' --glob '*.ss' --glob '*.scm' --glob '*.py' --glob '*.just' --glob '*.lean' --glob '*.qnt' --glob 'gerbil.pkg' . || status=$?
    case "$status" in
      0) echo 'downstream product coupling found in the independent package' >&2; exit 1 ;;
      1) echo 'YUANXU-PACKAGE-INDEPENDENCE-OK' ;;
      *) exit "$status" ;;
    esac

# Runtime issuer observations are checked independently by the Lean projection.
check-issuer-projection trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run IssuerProjectionCheck.lean "{{ trace }}"

# Independent decoder consumes actual runtime alias/cache observations.
check-metadata-allocation trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run MetadataAllocationCheck.lean "{{ trace }}"

check-store-lowering trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run StoreLoweringCheck.lean "{{ trace }}"

check-artifact-closure trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run ArtifactClosureCheck.lean "{{ trace }}"

check-issued-loading trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run IssuedLoadingCheck.lean "{{ trace }}"

check-build-publication trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run CoreBuildPublicationCheck.lean "{{ trace }}"

check-build-handoff trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run CoreBuildHandoffCheck.lean "{{ trace }}"

check-store-recovery trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run CoreStoreRecoveryCheck.lean "{{ trace }}"

check-approved-recovery trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run CoreApprovedRecoveryCheck.lean "{{ trace }}"

check-source-loader trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run SourceLoaderCheck.lean "{{ trace }}"

check-test-groups:
    GERBIL_PATH="${GERBIL_PATH:-$PWD/.gerbil}" gxi {{ gerbil_test_runtime_options }} -e '(import (only-in "./dev/ci-inventory.ss" main))' -e '(main "--check")'
