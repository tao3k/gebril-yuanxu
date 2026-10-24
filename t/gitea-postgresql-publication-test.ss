;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures
               ServicesFixture RepositoryServicesFixture write-source refused)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export gitea-postgresql-publication-test test-cleanup!)
(def completed 0)
(def (test-cleanup!)
  (unless (= completed 11) (error "incomplete service controls" completed))
  (displayln "GITEA-POSTGRESQL-PUBLICATION: 11 cases completed"))
(def gitea-postgresql-publication-test
  (test-suite "Maintained Gitea and PostgreSQL publications"
    (yuanxu-test-fixture "repository module sources publish their actual defaults"
      (fixture RepositoryServicesFixture)
      (with-slots (publication) fixture
        (def parent (.get publication value))
        (defvalues (receipt next failure) (.call publication .publish parent parent))
        (check-equal? failure #f)
        (check-equal? (.get receipt accepted?) #t)
        (check-equal? (.get next plan postgresql port) 5432)
        (check-equal? (.get next plan gitea database-port) 5432)
        (check-equal? (length (.get publication context contributions)) 2)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "cached parent retains its plan and child reads final port"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def cached (.get parent plan))
        (check-equal? (.get cached postgresql port) 5432)
        (check-equal? (.get cached gitea database-port) 5432)
        (.def (Release @ parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        (def evidence (.call (.get publication contract) .admit Release (.get publication context)))
        (check-equal? (.get evidence accepted?) #t)
        (defvalues (receipt next failure) (.call publication .publish parent Release))
        (check-equal? failure #f)
        (check-equal? (.get receipt accepted?) #t)
        (check-equal? (eq? (.get receipt candidate) next) #t)
        ;; Direct and published admission share the exact descriptor and bound
        ;; Context. Each may normalize a new receiver; compare its semantics
        ;; and internal alias, not identity across two separate invocations.
        (check-equal? (.get evidence accepted?) (.get receipt accepted?))
        (check-equal? (eq? (.get evidence admission-contract)
                          (.get receipt admission-contract)) #t)
        (check-equal? (eq? (.get evidence context) (.get receipt context)) #t)
        (check-equal? (.get evidence diagnostics) (.get receipt diagnostics))
        (check-equal? (.get evidence candidate plan postgresql port)
                      (.get next plan postgresql port))
        (check-equal? (eq? (.get evidence candidate config)
                          (.get evidence candidate plan configuration)) #t)
        ;; Lists are normalized, but the plan aliases the one final config.
        (check-equal? (eq? next Release) #f)
        (check-equal? (eq? (.get next config) (.get next plan configuration)) #t)
        (check-equal? (eq? (.get cached configuration) (.get parent config)) #t)
        (def config-evidence (car (.get receipt responsibility-evidence)))
        (check-equal? (eq? (.get config-evidence candidate) (.get next config)) #t)
        (def database-evidence (car (.get config-evidence responsibility-evidence)))
        (check-equal? (eq? (.get database-evidence candidate) (.get next config postgresql)) #t)
        (check-equal? (.get next plan postgresql port) 5433)
        (check-equal? (.get next plan gitea database-port) 5433)
        (check-equal? (.get cached postgresql port) 5432)
        (.def (Frozen @ Release) plan: cached)
        (refused publication parent Frozen)
        ;; Equal scalar projections cannot authorize a captured pre-normalized config.
        (def raw-config (.get Release config))
        (.def (Captured @ Release)
          plan: (.o configuration: raw-config postgresql: (.o port: 5433)
                    gitea: (.o database-port: 5433)))
        (def rejected (.call (.get publication contract) .admit Captured (.get publication context)))
        (check-equal? (.get rejected accepted?) #f)
        (check-equal? (.get (car (.get rejected diagnostics)) kind) 'stale-parent-plan)
        (check-equal? (.get rejected candidate plan postgresql port) 5433)
        (check-equal? (memq 'services/unused (.get selection selected-graph module-order)) #f)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "both independently published requirements survive and conflict"
      (fixture (.cc ServicesFixture postgres-ports: '(5433) gitea-ports: '(5440)))
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (.def (Release @ parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        (def evidence (.call (.get publication contract) .admit Release (.get publication context)))
        (check-equal? (.get evidence accepted?) #f)
        (def issue (car (.get evidence obligation-evidence)))
        (check-equal? (.get issue kind) 'unsatisfied-joint-port-requirements)
        (check-equal? (map (lambda (row) (.get row allowed-ports)) (.get issue constraints))
                      '((5433) (5440)))
        (check-equal? (map (lambda (row) (.get row origin owner)) (.get issue constraints))
                      '(applications/gitea-postgresql applications/gitea-postgresql))
        (check-equal? (map (lambda (row) (.get row source-origin path)) (.get issue constraints))
                      '((allowed-ports) (allowed-ports)))
        (refused publication parent Release)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "client mismatch and invalid port refuse before plan publication"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (.def (Mismatch @ parent)
          config: =>.+ (.o gitea: =>.+ (.o database: =>.+ (.o port: 5440))))
        (def evidence (.call (.get publication contract) .admit Mismatch (.get publication context)))
        (check-equal? (.get (car (.get evidence diagnostics)) kind) 'connection-mismatch)
        (refused publication parent Mismatch)
        (.def (Invalid @ parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: "5433"))))
        (def bad (.call (.get publication contract) .admit Invalid (.get publication context)))
        (check-equal? (.get (car (.get bad diagnostics)) path) '(config postgresql settings port))
        (refused publication parent Invalid)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "explicit client config is retained rather than silently rebound"
      (fixture (.cc ServicesFixture client-port: 5440))
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def evidence (.call (.get publication contract) .admit parent (.get publication context)))
        (check-equal? (.get parent config gitea database port) 5440)
        (def issue (car (.get evidence diagnostics)))
        (check-equal? (.get issue kind) 'connection-mismatch)
        (check-equal? (.get issue expected) 5432)
        (check-equal? (.get issue expected-path) '(config postgresql settings port))
        (check-equal? (.get issue origin path) '(database port))
        (check-equal? (.get issue origin kind) 'json-field)
        (check-equal? (path-strip-directory (.get issue origin source)) "gitea.json")
        (check-equal? (path-strip-directory (.get issue expected-origin source)) "postgresql.json")
        (refused publication parent parent)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "closed field contracts refuse typo without evaluating its value"
      (fixture ServicesFixture)
      (with-slots (publication) fixture
        (def parent (.get publication value))
        (.def (Typo @ parent)
          config: =>.+ (.o postgresql: =>.+
                    (.o settings: =>.+ (.o prot: (error "unknown field must remain cold")))))
        (def evidence (.call (.get publication contract) .admit Typo (.get publication context)))
        (check-equal? (.get evidence accepted?) #f)
        (def failure (car (.get evidence diagnostics)))
        (check-equal? (.get failure kind) 'unknown-field)
        (check-equal? (.get failure path) '(config postgresql settings prot))
        (refused publication parent Typo)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "database contextual obligation survives canonical value validation"
      (fixture ServicesFixture)
      (with-slots (publication) fixture
        (def parent (.get publication value))
        (def cached (.get parent plan))
        (def original (.get publication contract))
        (.def (Restricted @ (.get original database-contract))
          .obligations:
          (lambda (candidate _context)
            (if (= (.get candidate settings port) 5432) '()
              (list (.o kind: 'database-port-policy path: '(settings port))))))
        (.def (Contract @ original) database-contract: Restricted)
        (.def (Release @ parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        ;; Direct admission isolates delegation; publication coverage is tested
        ;; separately with its real, descriptor-bound Context above.
        (def evidence (.call Contract .admit Release #f))
        (check-equal? (.get evidence accepted?) #f)
        (def configuration (car (.get evidence responsibility-evidence)))
        (def database (car (.get configuration responsibility-evidence)))
        (check-equal? (.get database accepted?) #f)
        (check-equal? (.get (car (.get database diagnostics)) kind) 'database-port-policy)
        (check-equal? (eq? (.get database candidate) (.get evidence candidate config postgresql)) #t)
        (check-equal? (if (memq Restricted (compute-precedence-list! (.get database admission-contract))) #t #f) #t)
        (check-equal? (.get cached postgresql port) 5432)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "deep source mutation refuses even when leaf identity is unchanged"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def row (car (.get publication context contributions)))
        (def middle (.get row origin record scope requirements))
        (.put! middle 'postgresql (.get row payload))
        (refused publication parent parent "contribution object changed")
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "child obligation cannot authorize a source changed within admission"
      (fixture ServicesFixture)
      (with-slots (root publication) fixture
        (def parent (.get publication value))
        (def original (.get publication contract))
        (def path (path-expand "modules/services/postgresql/postgresql.json" root))
        (.def (Changing @ (.get original database-contract))
          .obligations:
          (lambda (_candidate _context)
            ;; Explicit negative fixture effect, never a normal domain rule.
            (write-source path (string-append (module-source-read path) "\n"))
            '()))
        (.def (Contract @ original) database-contract: Changing)
        (def failure (with-catch values (lambda () (.call Contract .admit parent #f))))
        (check-equal? (Error? failure) #t)
        (check-equal? (Error-message failure) "configuration source changed")
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "omitted and substituted real contribution rows refuse"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def context (.get publication context))
        (def rows (map values (.get context contributions)))
        (.put! context 'contributions (cdr rows))
        (refused publication parent parent "incomplete contribution collection")
        (def origin (.get (car rows) origin))
        (def replacement
          (.cc origin source: (.get (cadr rows) origin source)))
        (.put! context 'contributions
          (cons (.cc (car rows) origin: replacement) (cdr rows)))
        (refused publication parent parent "substituted contribution origin")
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "real service role source edit refuses an otherwise valid release"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def path (path-expand "modules/services/postgresql/config.ss" root))
        (write-source path (string-append (module-source-read path) "\n; source changed\n"))
        ;; Current reader registers role compilation sources. Its byte guard
        ;; refuses first; retain the exact path/reason rather than accepting
        ;; any generic refusal or changing production diagnostic ordering.
        (refused publication parent parent "stale prepared build source" path)
        (set! completed (+ completed 1))))))
