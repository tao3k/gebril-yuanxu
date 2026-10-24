;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Storage capability controls, separate from real Scenario integration.
(import :std/test :clan/poo/object
        (only-in :std/error Error?)
        (only-in :std/db/interface sql-error?)
        (only-in :yuanxu/ops/objects ProcessScript.)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture)
        "./qualification/build-publication/persistent-head")
(export persistent-head-store-test)
(def persistent-head-store-test
  (test-suite "Persistent selected-head storage capability"
    (yuanxu-test-fixture "independent client, stale requests, ABA and fence"
      (fixture DirectoryFixture)
      (with-slots (root) fixture
        (def path (path-expand "head.sqlite" root))
        (def owner (persistent-head path))
        (.call owner initialize "selected-graph" "parent-5432")
        (def token (.call owner issue "selected-graph" "child-5433" 0 0))
        (def stale (.call owner issue "selected-graph" "stale-parent" 0 0))
        (def (worker operation argument)
          (run-script (.cc ProcessScript. 'command
            (list "just" "persistent-head-worker" path operation argument) 'timeout 30)
            stderr-redirection: #f))
        (check-equal? (.get (worker "commit" token) status) 0)
        (def recovered (worker "inspect" ""))
        (check-equal? (.get recovered status) 0)
        (check-equal? (call-with-input-string (.get recovered output) read)
                      '#(1 1 "selected-graph" "child-5433"))
        (check-exception (.call owner commit stale) Error?)
        (check-exception (.call owner commit token) Error?)
        (check-exception (.call owner commit "unknown") Error?)
        (check-exception (.call owner issue "other-graph" "other" 1 1) Error?)
        (def back (.call owner issue "selected-graph" "parent-5432" 1 1))
        (.call owner commit back)
        (check-equal? (.call owner inspect) '#(2 2 "selected-graph" "parent-5432"))
        (check-exception (.call owner initialize "replacement" "reset") sql-error?)
        (check-equal? (.call owner inspect) '#(2 2 "selected-graph" "parent-5432"))
        (check-exception (.call owner commit stale) Error?)
        (check-exception (.call owner issue "selected-graph" "bad-fence" 2 1) Error?)))))
