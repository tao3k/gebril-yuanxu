;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object (only-in :yuanxu/configuration/json config-field-origin))
(export Application. gitea-application gitea-policy)
;; Configuration is supplied by the admitted dependency scope at publication.
(.def (Application. @ [] config)
  plan:
  (.o configuration: config
      postgresql: (.o port: (.get config postgresql settings port))
      gitea: (.o database-port: (.get config gitea database port))))

(def (gitea-application database client)
  (.cc Application.
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

(def (gitea-policy configuration document)
  (.o requirements:
      (.o database-port:
          (.o allowed-ports: (.get configuration allowed-ports)
              origin: (config-field-origin document '(allowed-ports) (.get configuration allowed-ports))))))
