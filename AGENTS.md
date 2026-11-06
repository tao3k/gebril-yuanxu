<!--
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-->

# Yuanxu Module System constraints

- Follow `module-system/design/44-current-project-programming-style.org`, especially its import/build/performance and formal correspondence rules.
- Preserve `yuanxu!`, Interface configuration and native POO `.get`. One init-owned `std-make-spec` selects source owners and dependency closure; Gerbil owns packages, compilation and artifact lookup. Do not add a loader or a cache layer.
- Source projection must use `call-with-build-input-path` in the existing build entry. Preserve prerequisite order, keep outputs as native fallback, restore the caller's path on success/failure, and refuse a mutated input epoch. Do not move this responsibility into downstream environment flags or force business scopes to prepare a spec.
- Measure ordinary `.get` through the existing callback-free operation counters. Open source observers deliberately select the guarded callback path; use them for adversarial controls and retain their tests, not as the normal-path performance workload.
- Run Scheme tests through the heap-fenced Justfile entrypoints, serially. Resolution/projection changes require `just test-build-input-context-mutations <artifact-dir>`, `t/module-publication-test.ss` and `t/module-testing-source-admission-test.ss`. The mutation gate runs the order/admission suites before and after isolated faults; a timeout or compiler failure is not a rejected mutation. Real Lab acceptance belongs in Lab's tests, never in this independent package. Preserve existing budgets and negative controls.
