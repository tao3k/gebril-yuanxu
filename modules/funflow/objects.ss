;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in "control-plane/agent-harness-vocabulary.ss"
                 +yuanxu-agent-operation-kinds+ +yuanxu-runtime-snapshot-statuses+)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in "control-plane/signatures.ss" Fun String validate)
        (only-in "types.ss" JobResultContract)
        ;; This role publishes these combinators, not the aggregate control
        ;; plane (including Agent harnesses and unrelated syntax facades).
        (only-in "control-plane/flow.ss"
                 flow-arr flow-then flow-fanout flow-map flow-bind
                 flow-first flow-second conditional-flow try-flow
                 return-flow cached-pure-flow)
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
  .run: (validate (Fun JobResultContract <- String)
          (lambda (workspace) (run-job job workspace))))
(.def FunflowModule.
  runtime-vocabulary:
  (.o operation-kinds: +yuanxu-agent-operation-kinds+
      snapshot-statuses: +yuanxu-runtime-snapshot-statuses+)
  store: (.o (put-dir-flow) (get-dir-flow) (store-flow))
  flow: (.o (flow-arr) (flow-then) (flow-fanout) (flow-map) (flow-bind)
            (flow-first) (flow-second) (conditional-flow) (try-flow)
            (return-flow) (cached-pure-flow))
  pipeline-graph: yuanxu-funflow-poo-pipeline->functional-dag
  prototypes: (.o Task: Task. Job: Job. check: funflow-check pipeline: funflow-pipeline))
