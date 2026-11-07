;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Scenario public behavior only; no Core provenance/relocation machinery.
(import :std/test :clan/poo/object
        (only-in "../objects.ss" application-scope)
        (only-in "../gitea/objects.ss" gitea-application)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export config-test)
;; Minimal dependency scopes supply the actual public constructor's input shape.
;; Only Scenario is demanded; admission/publication metadata is not simulated.
(def (scenario supplied defaults)
  (def Base (.o config: (.o settings: (.o port: 5432) allowed-ports: '(5432 5433))
                   document: (.o value: (.o settings: (.o port: 5432)))))
  ;; The final scope can be a downstream .def; its JSON baseline stays upstream.
  (.def (database @ Base) config: supplied)
  (def client (.o config: (.o database: (.o) allowed-ports: '(5432 5433))
                     document: (.o value: (.o)) application: gitea-application))
  (.get (application-scope database client
          (.o postgresql: defaults gitea: (.o database: (.o)))) Scenario))
(def config-test
  (test-suite "Scenario ordinary defaults and explicit service data"
    (yuanxu-test-case "Scenario fills a missing value in a compatible supplied scope"
      (def value (scenario (.o settings: (.o) allowed-ports: '(5432 5433))
                          (.o settings: (.o port: 5433))))
      (check-equal? (.get value config postgresql settings port) 5433)
      (check-equal? (.get value config gitea database port) 5433)
      (check-equal? (.get value config postgresql allowed-ports) '(5432 5433)))
    (yuanxu-test-case "final derived scope wins over defaults and old JSON baseline"
      (def value (scenario (.o settings: (.o port: 5440)) (.o settings: (.o port: 5433))))
      (check-equal? (.get value config postgresql settings port) 5440)
      (check-equal? (.get value config gitea database port) 5440))
    (yuanxu-test-case "explicit null is not filled as missing"
      (def value (scenario (.o settings: 'json-null) (.o settings: (.o port: 5433))))
      (check-equal? (.get value config postgresql settings) 'json-null))))
