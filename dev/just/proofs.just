# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# One Core Lake project; LeanPoo is its immutable dependency.
proofs: proofs-quint proofs-lean

proofs-lean:
    cd dev/proofs/lean && timeout 120s lake build

# Tool/backend bootstrap is preparation, never an accepted proof receipt.
prepare-quint:
    npm ci --prefix dev/proofs/quint --no-audit --no-fund
    python3 dev/proofs/quint/prepare.py

# All maintained finite models are Quint; receipts remain local artifacts.
proofs-quint receipt="/private/tmp/core-quint-proof.ss":
    python3 -m unittest discover -s dev/proofs/quint -p test_typecheck.py
    python3 dev/proofs/quint/check.py --receipt "{{ receipt }}"
