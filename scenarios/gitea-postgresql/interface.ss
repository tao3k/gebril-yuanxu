;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def GiteaPostgreSQL
  identity: 'applications/gitea-postgresql
  core:
  (.o requires: (.o PostgreSQL: (.o module-id: 'services/postgresql contract: ServiceScopeContract)
                    Gitea: (.o module-id: 'services/gitea contract: ServiceScopeContract))
      scope-contract: ApplicationScopeContract
      admissions: (.o Application: (.o export-path: '(Scenario) contract-path: '(types Application)))
      contributions:
      (.o postgresql-port: (.o target-owner: 'applications/gitea-postgresql target-admission: 'Application
                              export-path: '(requirements postgresql))
          gitea-port: (.o target-owner: 'applications/gitea-postgresql target-admission: 'Application
                         export-path: '(requirements gitea)))
      exports: (application-scope PostgreSQL Gitea Config))
  features: (.o))
