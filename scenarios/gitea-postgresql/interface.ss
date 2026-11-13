;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :tao3k/yuanxu/module-system/source/declaration .def)
        (only-in "postgresql/config.ss" PostgreSQLScope)
        (only-in "gitea/config.ss" GiteaScope))
(.def GiteaPostgreSQL
  identity: 'applications/gitea-postgresql
  core:
  (.o scope-contract: ApplicationScopeContract
      admissions: (.o Application: (.o export-path: '(Scenario) contract-path: '(types Application)))
      contributions:
      (.o postgresql-port: (.o target-owner: 'applications/gitea-postgresql target-admission: 'Application
                              export-path: '(requirements postgresql))
          gitea-port: (.o target-owner: 'applications/gitea-postgresql target-admission: 'Application
                         export-path: '(requirements gitea)))
      exports: (application-scope PostgreSQLScope GiteaScope Config))
  features: (.o))
