;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :yuanxu/configuration/json config-defaults))
(export application-scope)
(def (application-scope database client defaults)
  (.o Scenario: ((.get client application)
                 (config-defaults (.get defaults postgresql) (.get database config))
                 (config-defaults (.get defaults gitea) (.get client config)))
      requirements: (.o postgresql: (.get database policy requirements database-port)
                       gitea: (.get client policy requirements database-port))
      types:
      (.o Application:
          (.cc (.get client types Application)
            database-contract: (.get database types Config)
            port-type: (.get database types port)
            documents: (.o postgresql: (.get database document) gitea: (.get client document))))))
