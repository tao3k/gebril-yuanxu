;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native receiver/normalization qualification, without Loader or publication.
(import :std/test :clan/poo/object :clan/poo/object-contract
        (only-in :clan/poo/mop define-type validate Object Bool Function)
        (only-in :clan/poo/number IntegerRange)
        (only-in :clan/poo/type List)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence))
(export object-contract-plan-identity-test test-cleanup!)

;; A source-matched copy of modules/gitea/objects.ss's pure constructor only.
;; Isolates normalization from the generated module prelude and JSON provenance.
;; This is a test fixture, not qualification of module/Loader integration.
(.def (ApplicationFixture. @ [] config)
  plan:
  (.o configuration: config
      postgresql: (.o port: (.get config postgresql settings port))
      gitea: (.o database-port: (.get config gitea database port))))
(def (application-fixture database client)
  (.cc ApplicationFixture.
    config:
    (.o (:: @ [] postgresql)
      postgresql: database
      gitea:
      (.o (:: @ client)
        database:
        (let (supplied (.get client database))
          (if (object? supplied)
            (.o (:: @ supplied) (port ? (.get postgresql settings port)))
            supplied))))))

(def Port (IntegerRange min: 1 max: 65535))
(def Settings (.cc ObjectContract. responsibilities: (.o port: Port)))
(def Database (.cc ObjectContract. responsibilities:
                (.o settings: Settings allowed-ports: (List Port))))
(def Client (.cc ObjectContract. responsibilities:
              (.o database: Settings allowed-ports: (List Port))))
(def Configuration (.cc ObjectContract. responsibilities:
                     (.o postgresql: Database gitea: Client)))
(def DatabasePlan (.cc ObjectContract. responsibilities: (.o port: Port)))
(def ClientPlan (.cc ObjectContract. responsibilities: (.o database-port: Port)))
(def Plan (.cc ObjectContract. responsibilities:
            (.o configuration: Configuration postgresql: DatabasePlan gitea: ClientPlan)))
(def Application (.cc ObjectContract. responsibilities: (.o config: Configuration plan: Plan)))

;; Test-only extension: Function adds checked behavior to list normalization.
;; It is not a new public Gitea setting or a replacement for the production schema.
(def Policy (Function (list Bool) (list Port)))
(def PolicyConfiguration
  (.o (:: @ Configuration) responsibilities: =>.+ (.o port-policy: Policy)))
(def RepeatedPlan
  (.o (:: @ Plan) responsibilities: =>.+ (.o configuration: PolicyConfiguration)))
(def RepeatedApplication
  (.o (:: @ Application) responsibilities: =>.+
    (.o config: PolicyConfiguration plan: RepeatedPlan)))
;; The alias is checked by identity below; normalize the canonical config once.
(def AliasPlan (.o (:: @ Plan) responsibilities: =>.+ (.o configuration: Object)))
(def ScalarApplication
  (.o (:: @ Application) responsibilities: =>.+ (.o plan: AliasPlan)))
(def SingleApplication
  (.o (:: @ Application) responsibilities: =>.+
    (.o config: PolicyConfiguration plan: AliasPlan)))

(def (application-issues candidate)
  (def config (.get candidate config))
  (def plan (.get candidate plan))
  (def port (.get config postgresql settings port))
  (append
    (if (= port (.get config gitea database port)) '()
      (list (.o kind: 'connection-mismatch path: '(config gitea database port))))
    (if (and (eq? config (.get plan configuration))
             (= port (.get plan postgresql port))
             (= (.get config gitea database port) (.get plan gitea database-port)))
      '() (list (.o kind: 'stale-parent-plan path: '(plan))))))
(define-type (Admission @ YuanxuContract.)
  .classify:
  (lambda (candidate context)
    (def issues (application-issues candidate))
    (yuanxu-classification-evidence 'test/service-normalization candidate
      (null? issues) issues context)))
(def (admit shape candidate)
  (.call (.cc Admission value-contract: shape) .admit candidate #f))
(def (kinds evidence) (map (cut .get <> kind) (.get evidence diagnostics)))
(def (parent)
  (application-fixture
    (.o settings: (.o port: 5432) allowed-ports: '(5432 5433))
    (.o database: (.o) allowed-ports: '(5432 5433))))
(def (policy-parent)
  (def base (parent))
  (.o (:: @ base) config: =>.+ (.o port-policy: (lambda (_port) #t))))
(def (release base)
  (.o (:: @ base)
    config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433)))))

(def completed 0)
(def (done!) (set! completed (+ completed 1)))
(def (test-cleanup!)
  (unless (= completed 6) (error "incomplete normalization controls" completed))
  (displayln "OBJECT-CONTRACT-PLAN-IDENTITY: 6 cases completed"))
(def object-contract-plan-identity-test
  (test-suite "Canonical config and final plan normalization"
    (yuanxu-test-case "repeated list normalization breaks final alias after parent cache"
      (def base (parent))
      (def cached (.get base plan))
      (check-equal? (.get cached postgresql port) 5432)
      (def child (release base))
      (def evidence (admit Application child))
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (kinds evidence) '(stale-parent-plan))
      (def checked (.get evidence candidate))
      (check-equal? (eq? checked child) #f)
      (check-equal? (eq? (.get checked config) (.get checked plan configuration)) #f)
      (check-equal? (.get checked config gitea database port) 5433)
      (check-equal? (.get checked plan postgresql port) 5433)
      (check-equal? (.get cached gitea database-port) 5432)
      (done!))
    (yuanxu-test-case "canonical config preserves service alias after parent cache"
      (def base (parent))
      (def cached (.get base plan))
      (def child (release base))
      (def evidence (admit ScalarApplication child))
      (def checked (.get evidence candidate))
      (check-equal? (.get evidence accepted?) #t)
      (check-equal? (eq? checked child) #f)
      (check-equal? (eq? (.get checked config) (.get checked plan configuration)) #t)
      (check-equal? (.get checked config gitea database port) 5433)
      (check-equal? (.get checked plan postgresql port) 5433)
      (check-equal? (.get cached gitea database-port) 5432)
      (done!))
    (yuanxu-test-case "explicit client mismatch survives normalization and refuses"
      (def base (parent))
      (def cached (.get base plan))
      (def child (release base))
      (.def (Explicit @ child)
        config: =>.+ (.o gitea: =>.+ (.o database: =>.+ (.o port: 5432))))
      (def evidence (admit ScalarApplication Explicit))
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (kinds evidence) '(connection-mismatch))
      (check-equal? (.get (.get evidence candidate) config gitea database port) 5432)
      (check-equal? (.get cached postgresql port) 5432)
      (done!))
    (yuanxu-test-case "normalizing config independently through plan breaks alias"
      (def base (policy-parent))
      (def cached (.get base plan))
      (def child (release base))
      (def evidence (admit RepeatedApplication child))
      (def checked (.get evidence candidate))
      (check-equal? (eq? checked child) #f)
      (check-equal? (eq? (.get checked config) (.get checked plan configuration)) #f)
      (check-equal? (.get checked config gitea database port) 5433)
      (check-equal? (.get checked plan gitea database-port) 5433)
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (kinds evidence) '(stale-parent-plan))
      (check-equal? (.get cached postgresql port) 5432)
      (done!))
    (yuanxu-test-case "single canonical normalization rebinds lexical plan automatically"
      (def base (policy-parent))
      (def cached (.get base plan))
      (def child (release base))
      (def evidence (admit SingleApplication child))
      (def checked (.get evidence candidate))
      (check-equal? (eq? checked child) #f)
      (check-equal? (.get evidence accepted?) #t)
      (check-equal? (eq? (.get checked config) (.get checked plan configuration)) #t)
      (check-equal? (.get checked plan postgresql port) 5433)
      (check-equal? (.get checked plan gitea database-port) 5433)
      (check-equal? ((.get checked config port-policy) 5433) #t)
      (check-exception ((.get checked config port-policy) "5433") error?)
      (check-equal? (.get cached postgresql port) 5432)
      (done!))
    (yuanxu-test-case "single normalization rejects cached parent and captured raw child plans"
      (def base (policy-parent))
      (def cached (.get base plan))
      (def child (release base))
      (.def (Frozen @ child) plan: cached)
      (check-equal? (.get (admit SingleApplication Frozen) accepted?) #f)
      (check-equal? (kinds (admit SingleApplication Frozen)) '(stale-parent-plan))
      (def raw-config (.get child config))
      (.def (Captured @ child)
        plan: (.o configuration: raw-config
                  postgresql: (.o port: 5433) gitea: (.o database-port: 5433)))
      (def evidence (admit SingleApplication Captured))
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (kinds evidence) '(stale-parent-plan))
      (check-equal? (.get (.get evidence candidate) plan postgresql port) 5433)
      (check-equal? (.get cached postgresql port) 5432)
      (done!))))
