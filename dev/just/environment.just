# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# Native make and its backend executor share this bounded CPU budget.
# Explicit caller/CI budgets win; test execution remains serial and heap fenced.
export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", if num_cpus() =~ '^[1-4]$' { num_cpus() } else { '4' })

gerbil_test_max_heap := env_var_or_default("GERBIL_TEST_MAX_HEAP", "2G")

gerbil_test_debug := env_var_or_default("GERBIL_TEST_DEBUG", "q")

gerbil_test_runtime_options := "-:max-heap=" + gerbil_test_max_heap + ",debug=" + gerbil_test_debug
