;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object :clan/poo/object-contract
        (only-in :clan/poo/mop define-type Object Any)
        (only-in :clan/poo/number IntegerRange)
        (only-in :clan/poo/type List)
        (only-in :clan/poo/object-diagnostics diagnostic-then)
        (only-in :std/list/list every)
        (only-in :core/types PooFlowContract.
                 poo-flow-predicate-contract poo-flow-classification-evidence)
        (only-in :core/admission/source SourceAdmissionContract. source-diagnose-at)
        (only-in :core/configuration/diagnostics config-diagnostic-locator))
(export ApplicationContract GiteaConfigContract GiteaScopeContract PostgreSQLScopeContract)
(def (fields? value names)
  (and (object? value) (every (lambda (name) (.slot? value name)) names)))
(define-type (GiteaValueContract. @ ObjectContract. port-type)
  identity: 'gitea/config-value
  responsibilities:
  (.o database: (.cc ObjectContract. responsibilities: (.o port: port-type))
      allowed-ports: (List port-type)))
(define-type (GiteaConfigContract @ PooFlowContract.)
  identity: 'gitea/config
  value-contract: (.cc GiteaValueContract. port-type: (IntegerRange min: 1 max: 65535))
  .classify: (lambda (candidate context)
               (poo-flow-classification-evidence identity candidate #t '() context)))
;; Root value validation owns normalization. Contextual descendants retain the
;; service classifiers/obligations and must admit that exact checked child.
(define-type (ConfigurationAdmission. @ PooFlowContract. database-contract)
  identity: 'gitea/configuration-context
  responsibilities:
  (.o postgresql: (.o (:: @ database-contract) value-contract: #f)
      gitea: (.o (:: @ GiteaConfigContract) value-contract: #f))
  .classify: (lambda (candidate context)
               (poo-flow-classification-evidence identity candidate #t '() context)))
;; These scope probes inspect names only, rather than normalizing lazy exports.
(def PostgreSQLScopeContract
  (poo-flow-predicate-contract 'gitea/postgresql-dependency
    (lambda (value)
      (and (fields? value '(config types))
           (fields? (.get value types) '(port Config))))
    (lambda (_v _c) '())))
(def GiteaScopeContract
  (poo-flow-predicate-contract 'gitea/scope
    (lambda (value) (fields? value '(config document application types policy))) (lambda (_v _c) '())))
(def (issue kind-value path-value actual-value)
  (.o kind: kind-value path: path-value actual: actual-value))
(def ApplicationEnvelope
  (.cc ObjectContract. responsibilities: (.o config: Object plan: Object)))
(def ConfigEnvelope
  (.cc ObjectContract. responsibilities: (.o postgresql: Object gitea: Object)))
(define-type (ApplicationValueContract. @ ObjectContract. database-type port-type)
  identity: 'gitea/application-value
  client-type: (.cc GiteaValueContract. port-type: port-type)
  config-type: (.cc ObjectContract. responsibilities:
                (.o postgresql: database-type gitea: client-type))
  plan-type: (.cc ObjectContract. responsibilities:
              (.o configuration: Object
                  postgresql: (.cc ObjectContract. responsibilities: (.o port: port-type))
                  gitea: (.cc ObjectContract. responsibilities: (.o database-port: port-type))))
  responsibilities: (.o config: config-type plan: plan-type)
  ;; Stage diagnosis so null server settings cannot force the derived client.
  preflight:
  (foldr diagnostic-then (lambda (_value _path) '())
    (list (cut diagnose ApplicationEnvelope <> <>)
          (source-diagnose-at ConfigEnvelope '(config))
          (source-diagnose-at database-type '(config postgresql))
          (source-diagnose-at client-type '(config gitea))
          (source-diagnose-at plan-type '(plan)))))
(def (application-issues candidate)
  (def database (.get candidate config postgresql))
  (def client (.get candidate config gitea))
  (cond
     ((not (= (.get database settings port) (.get client database port)))
      (list (.cc (issue 'connection-mismatch '(config gitea database port) (.get client database port))
        expected: (.get database settings port)
        expected-path: '(config postgresql settings port))))
     ((not (and (eq? (.get candidate plan configuration) (.get candidate config))
                (= (.get candidate plan postgresql port) (.get database settings port))
                (= (.get candidate plan gitea database-port) (.get client database port))))
      (list (issue 'stale-parent-plan '(plan) (.get candidate plan))))
     (else '())))

(def (port-contributions requirement-type candidate rows _context)
  (def effective-port (.get candidate config postgresql settings port))
  (def constraint-values
    (map (lambda (row)
           (.o allowed-ports: (.get row payload allowed-ports)
               origin: (.get row origin)
               source-origin: (.get row payload origin)))
         rows))
  (def (satisfied? row)
    (let (ports (.get row allowed-ports))
      (and (null? (diagnose requirement-type row))
           (memv effective-port ports))))
  (if (every satisfied? constraint-values)
    '()
    (list (.o kind: 'unsatisfied-joint-port-requirements
              path: '(config postgresql settings port) actual: effective-port constraints: constraint-values))))
(.def (ApplicationContract @ SourceAdmissionContract. database-contract port-type documents)
  source-inputs: (append (.get documents postgresql source-inputs) (.get documents gitea source-inputs))
  .preflight: (.get value-contract preflight)
  .locate-diagnostic: (config-diagnostic-locator documents '(config))
  identity: 'gitea/application
  value-contract: (.cc ApplicationValueContract.
                    database-type: (.get database-contract value-contract) port-type: port-type)
  responsibilities:
  (.o config: (.cc ConfigurationAdmission. database-contract: database-contract))
  requirement-type: (.cc ObjectContract. responsibilities:
                      (.o allowed-ports: (List port-type) origin: Any source-origin: Any))
  .classify:
  (lambda (candidate context)
    (def issues (application-issues candidate))
    (poo-flow-classification-evidence identity candidate (null? issues) issues context))
  .contribution-obligations:
  (lambda (candidate rows context)
    (port-contributions requirement-type candidate rows context)))
