;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :yuanxu/t/qualification/module-scale/fixture DeclarationFixture)
        (only-in :yuanxu/module-system/building/test-observation ModuleTestingProfile.)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer))
(export module-retention-census-test)
(def (census fixture size)
  (def body-expansions 0)
  (def retention #f)
  (def previous (current-module-source-observer))
  (def (observe key amount)
    (def category (if (pair? key) (car key) key))
    (when (eq? category 'reader-body-expanded) (set! body-expansions (+ body-expansions amount)))
    (when (eq? category 'reader-retention) (set! retention (cdr key)))
    (when previous (previous key amount)))
  (def graph
    (parameterize ((current-module-source-observer observe))
      (.get fixture modules module-0 tests source selected-graph)))
  (def memory (yuanxu-debug-memory-snapshot 'retention-census collect?: #t))
  (check-equal? (length (.get graph module-order)) size)
  (check-equal? (.ref/cached (.get fixture modules module-0) 'scope) #f)
  (displayln "RETENTION-CENSUS modules=" size
    " expansions=" body-expansions " live-bytes=" (.get memory live-bytes)
    " reader-roots=" retention))
(.def (CensusProfile @ ModuleTestingProfile.) emit?: #t trace-enabled?: #t)
(def module-retention-census-test
  (test-suite "Bounded retained native read attribution through real init"
    (yuanxu-test-fixture "sixteen real modules"
      profile: CensusProfile (fixture (.cc DeclarationFixture size: 16)) (census fixture 16))
    (yuanxu-test-fixture "thirty-two real modules"
      profile: CensusProfile (fixture (.cc DeclarationFixture size: 32)) (census fixture 32))))
