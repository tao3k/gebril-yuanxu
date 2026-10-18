;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :core/ops/objects ProcessScript.)
        "control-plane/api.ss"
        (only-in "store.ss" put-dir-flow get-dir-flow store-flow)
        "func.ss" "config-prototypes.ss" "graph-projection.ss")
(export Task. Job. FunflowModule.)
(.def (Task. @ ProcessScript.) needs: '() after-start: #f)
(.def (Job. job [])
  name: 'job
  tasks: (.o)
  selected: '()
  finalizers: '()
  graph: (job-graph job)
  .run: (lambda (workspace) (run-job job workspace)))
(.def FunflowModule.
  store: (.o (put-dir-flow) (get-dir-flow) (store-flow))
  flow: (.o (flow-arr) (flow-then) (flow-fanout) (flow-map) (flow-bind)
            (flow-first) (flow-second) (conditional-flow) (try-flow)
            (return-flow) (cached-pure-flow))
  pipeline-graph: poo-flow-funflow-poo-pipeline->functional-dag
  prototypes: (.o Task: Task. Job: Job. check: funflow-check pipeline: funflow-pipeline))
