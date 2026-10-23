# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# Compiled/public sources must not reintroduce the removed Core namespace.
check-package-namespace:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    git grep -nE 'AgenticAILab|agentic-ai-lab-core|agentic-ai-lab-|:co[r]e/|:agentic-ai-lab/|package: core' -- '*.ss' '*.scm' '*.py' '*.nix' '*.yml' '*.yaml' '*.toml' '*.lean' '*.qnt' '*.sh' gerbil.pkg || status=$?
    case "$status" in
      0) echo 'removed Core namespace found' >&2; exit 1 ;;
      1) echo 'YUANXU-NAMESPACE-OK' ;;
      *) exit "$status" ;;
    esac

# Native issuer observations are checked independently by the Lean projection.
check-issuer-projection trace:
    cd dev/proofs/lean && timeout 120s lake env lean --run IssuerProjectionCheck.lean "{{ trace }}"

# Independent decoder consumes actual native alias/cache observations.
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
    #!/usr/bin/env bash
    set -euo pipefail
    export LC_ALL=C
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    just test-files all > "$scratch/all"
    test -s "$scratch/all"
    for group in bootstrap modules scale contracts objects scenarios runtime; do
      just test-files "$group" > "$scratch/$group"
      test -s "$scratch/$group"
      cat "$scratch/$group" >> "$scratch/groups"
      printf 'TEST-GROUP %s files=%s\n' "$group" "$(wc -l < "$scratch/$group")"
    done
    sort "$scratch/groups" > "$scratch/sorted"
    cmp "$scratch/all" "$scratch/sorted"
    printf 'TEST-GROUPS-OK\n'
