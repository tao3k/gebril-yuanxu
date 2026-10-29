# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# Native make and its backend executor share this bounded CPU budget.
# Explicit caller/CI budgets win; test execution remains serial and heap fenced.
export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", num_cpus())

gerbil_test_max_heap := env_var_or_default("GERBIL_TEST_MAX_HEAP", "2G")

gerbil_test_debug := env_var_or_default("GERBIL_TEST_DEBUG", "q")

gerbil_test_runtime_options := "-:max-heap=" + gerbil_test_max_heap + ",debug=" + gerbil_test_debug

# Darwin GCC must use the platform assembler/linker, even when Nix adds tools
# earlier in PATH. This is GCC's standard routing variable, not a Lab protocol.
gerbil_compiler_environment := if os() == "macos" { "env -u SDKROOT COMPILER_PATH=/usr/bin" } else { "env" }
