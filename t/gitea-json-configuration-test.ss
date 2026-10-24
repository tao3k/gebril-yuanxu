;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/source-closure yuanxu-bootstrap-contexts yuanxu-bootstrap-spec)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/configuration/json config-json-file config-defaults config-field-origin)
        (only-in :yuanxu/module-system/source/admission module-source-read)
        (only-in :yuanxu/t/qualification/service-publication/fixtures
               DirectoryFixture ServicesFixture write-source refused))
(export gitea-json-configuration-test test-cleanup!)
(def completed 0)
(def (test-cleanup!)
  (unless (= completed 4) (error "incomplete JSON controls" completed))
  (displayln "GITEA-JSON-CONFIGURATION: 4 cases completed"))
(def gitea-json-configuration-test
  (test-suite "JSON construction, sources and admission"
    (yuanxu-test-fixture "missing, null, false and explicit values stay distinct"
      (fixture DirectoryFixture)
      (with-slots (root) fixture
        (check-equal? (hash-key? (yuanxu-bootstrap-contexts) 'yuanxu/configuration/json) #t)
        (check-equal? (hash-key? (yuanxu-bootstrap-contexts) 'yuanxu/object-types/ports) #t)
        (def spec (yuanxu-bootstrap-spec (path-expand ".." (path-directory (this-source-file)))))
        (check-equal? (if (member '(gxc: "configuration/json") spec) #t #f) #t)
        (def path (path-expand "input.json" root))
        (write-source path "{\"settings\":{},\"nullable\":null,\"flag\":false,\"empty\":[],\"explicit\":5440}")
        (def document (config-json-file path))
        (def defaults (.o settings: (.o port: 5432) nullable: 1 flag: #t explicit: 5432))
        (def configuration (config-defaults defaults (.get document value)))
        (check-equal? (.get configuration settings port) 5432)
        (check-equal? (.get configuration nullable) 'json-null)
        (check-equal? (.get configuration flag) #f)
        (check-equal? (.get configuration empty) '())
        (check-equal? (.get configuration explicit) 5440)
        (check-equal? (.get (config-field-origin document '(settings port) 5432) presence) 'missing)
        (check-equal? (.get (config-field-origin document '(nullable) 'json-null) presence) 'null)
        (check-equal? (.get (config-field-origin document '(explicit) 5440) kind) 'json-field)
        (check-equal? (.get (config-field-origin document '(explicit) 5441) kind) 'derived-value)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "explicit JSON null is not the inherited server port"
      (fixture (.cc ServicesFixture client-port: 'null))
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (check-equal? (.get parent config gitea database port) 'json-null)
        (def evidence (.call (.get publication contract) .admit parent (.get publication context)))
        (check-equal? (.get evidence accepted?) #f)
        (def issue (car (.get evidence diagnostics)))
        (check-equal? (.get issue path) '(config gitea database port))
        (check-equal? (.get issue origin presence) 'null)
        (check-equal? (.get issue origin path) '(database port))
        (check-equal? (path-strip-directory (.get issue origin source)) "gitea.json")
        (refused publication parent parent)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "explicit null server settings rejects before forcing derived client"
      (fixture (.cc ServicesFixture null-settings?: #t))
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def evidence (.call (.get publication contract) .admit parent (.get publication context)))
        (check-equal? (.get evidence accepted?) #f)
        (def issue (car (.get evidence diagnostics)))
        ;; ObjectContract identifies the invalid subtree itself, not a port
        ;; that cannot exist beneath explicit null settings.
        (check-equal? (.get issue path) '(config postgresql settings))
        (check-equal? (.get issue origin path) '(settings))
        (check-equal? (.get issue origin presence) 'null)
        (refused publication parent parent)
        (set! completed (+ completed 1))))
    (yuanxu-test-fixture "JSON edit after cached parent refuses publication and direct admission"
      (fixture ServicesFixture)
      (with-slots (root selection publication) fixture
        (def parent (.get publication value))
        (def cached (.get parent plan))
        (check-equal? (.get cached postgresql port) 5432)
        (.def (Release @ parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        (def path (path-expand "modules/services/postgresql/postgresql.json" root))
        (write-source path (string-append (module-source-read path) "\n"))
        (refused publication parent Release "selected configuration asset changed")
        (check-exception
          (.call (.get publication contract) .admit Release (.get publication context)) error?)
        (check-equal? (.get cached postgresql port) 5432)
        (set! completed (+ completed 1))))))
