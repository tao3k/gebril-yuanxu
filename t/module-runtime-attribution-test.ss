;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object "./qualification/module-scale/fixture.ss"
        (only-in "./qualification/module-scale/workloads.ss" verify-runtime-attribution))
(export module-runtime-attribution-test)
(.def (StageAttributionFixture @ RuntimeAttributionFixture)
  .verify: (lambda (exports count root)
             (verify-runtime-attribution exports count root accounting?: 'stages)))
(.def (OpenStageAttributionFixture @ StageAttributionFixture)
  open-role-payloads?: #t
  .verify: (lambda (exports count root)
             (displayln "runtime-attribution lexical=full")
             (verify-runtime-attribution exports count root accounting?: 'stages)))
(def module-runtime-attribution-test
  (test-suite "Standard declaration/currentness/scope attribution controls"
    (declaration-scale-case "sixteen real declarations" 16 StageAttributionFixture)
    (declaration-scale-case "sixty-four real declarations" 64 StageAttributionFixture)
    (declaration-scale-case "sixty-four declarations with open payloads" 64 OpenStageAttributionFixture)))
