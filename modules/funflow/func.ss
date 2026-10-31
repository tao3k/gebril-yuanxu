;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Job projection reuses the functional Flow interpreter; Ops owns processes.
(import :clan/poo/object
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :yuanxu/graph/types-core yuanxu-graph yuanxu-graph-node yuanxu-graph-edge)
        (only-in :yuanxu/graph/algorithms yuanxu-graph-topological-order/acyclic)
        (only-in :yuanxu/ops/func validate-script)
        (only-in "control-plane/runtime-command-descriptor.ss"
                 runtime-command-fields->manifest make-stdout-runtime-command-descriptor)
        (only-in "control-plane/agent-harness.ss"
                 make-yuanxu-agent-operation make-yuanxu-dispatch-receipt make-yuanxu-workflow-run
                 yuanxu-agent-operation->alist yuanxu-dispatch-receipt->alist yuanxu-workflow-run->alist
                 make-yuanxu-agent-session yuanxu-agent-session->alist
                 make-yuanxu-agent-harness make-yuanxu-agent-profile
                 yuanxu-agent-harness->alist yuanxu-agent-profile->alist)
        (only-in :yuanxu/ops/types ProcessResultContract)
        (only-in "control-plane/signatures.ss" Fun Function Record String Symbol List validate)
        (only-in "control-plane/runtime-protocol.ss" AdapterResult)
        (only-in "control-plane/flow.ss" flow-compose external-flow flow-map)
        (only-in "control-plane/task.ss" execution-request-name execution-request-request execution-request-input)
        (only-in "control-plane/runtime-adapter.ss" make-runtime-adapter)
        (only-in "control-plane/runtime-protocol.ss" make-adapter-result adapter-result-value)
        (only-in "control-plane/strategy.ss" make-local-eager-strategy)
        (only-in "control-plane/runner.ss" make-runner runner-run run-result-value run-result-receipt))
(export job-graph job-flow run-job
        runtime-command-fields->manifest make-stdout-runtime-command-descriptor
        make-yuanxu-agent-operation make-yuanxu-dispatch-receipt make-yuanxu-workflow-run
        yuanxu-agent-operation->alist yuanxu-dispatch-receipt->alist yuanxu-workflow-run->alist
        make-yuanxu-agent-session yuanxu-agent-session->alist
        make-yuanxu-agent-harness make-yuanxu-agent-profile
        yuanxu-agent-harness->alist yuanxu-agent-profile->alist)

(def (symbol-set? values)
  (and (list? values) (every symbol? values)
       (= (length values) (length (delete-duplicates/hash values)))))
(def TaskRun (Function (list ProcessResultContract) '() rest: String))
(def (task-run task) (validate TaskRun (.get task .run)))
(def (admit-task tasks name)
  (unless (.slot? tasks name) (error "Funflow dependency has no task" name))
  (def task (validate-script (.ref tasks name)))
  (unless (and (.get task check-status) (symbol-set? (.get task needs)))
    (error "Funflow task requires a checked Ops action and distinct dependencies" name))
  ;; Preflight the callback without freezing a receiver-dependent .run slot.
  ;; Workspace refinement below must still bind the actual derived script.
  (task-run task)
  task)
(def (job-graph job)
  (let* ((tasks (.get job tasks)) (roots (.get job selected))
         (cleanup-names (.get job finalizers))
         (visited (make-hash-table-eq)) (names '()) (edges '()))
    (unless (and (symbol-set? roots) (symbol-set? cleanup-names))
      (error "Funflow targets and finalizers must be distinct symbol lists"))
    (def (visit name)
      (unless (hash-key? visited name)
        (hash-put! visited name #t)
        (let (task (admit-task tasks name))
          (for-each (lambda (dependency)
                      (visit dependency)
                      (set! edges (cons (yuanxu-graph-edge dependency name) edges)))
                    (.get task needs))
          (set! names (cons name names)))))
    (for-each visit roots)
    ;; Finalizers are exceptional-exit edges, not successful dependency edges.
    ;; Their trigger must be in the selected closure and they cannot spawn a
    ;; second unselected dependency closure while handling failure.
    (for-each
      (lambda (name)
        (let* ((task (admit-task tasks name)) (trigger (.get task after-start)))
          (unless (and (not (hash-key? visited name)) (null? (.get task needs))
                       (symbol? trigger) (hash-key? visited trigger))
            (error "invalid Funflow finalizer trigger" name trigger)))) cleanup-names)
    (let* ((graph-value (yuanxu-graph (.get job name)
                         (map yuanxu-graph-node (reverse names)) (reverse edges)))
           (order-value (yuanxu-graph-topological-order/acyclic graph-value)))
      (unless order-value (error "Funflow task dependency cycle" roots))
      (.o graph: graph-value order: order-value finalizers: cleanup-names))))

(def (job-results-type job)
  (apply Record
    (foldr (lambda (name fields)
             (cons (string->keyword (symbol->string name))
               (cons (list ProcessResultContract optional: #t) fields)))
           '() (.all-slots (.get job tasks)))))
(def (job-flow job projection workspace)
  (def Results (job-results-type job))
  (flow-compose (.get job name)
		(map (lambda (name)
		       (flow-map (string->symbol (string-append (symbol->string name) "/result"))
				 (external-flow name 'ops
						(.cc (admit-task (.get job tasks) name) 'directory workspace)
						(Fun AdapterResult <- Results))
				 (Fun Results <- AdapterResult)
				 adapter-result-value))
		     (.get projection order))
		(Fun Results <- Results)))
(def (unsupported-ops-operation _value)
  (error "Job Ops interpreter does not provide fetch or Store operations"))
(def (run-job job workspace)
  (unless (string? workspace) (error "Funflow execution requires a workspace" workspace))
  (let* ((projection (job-graph job)) (started (make-hash-table-eq))
         (results (.o)) (flow-receipt-value #f) (cleanup-failures '()) (primary-failure #f))
    (def (execute name script)
      (hash-put! started name #t)
      (let (receipt ((task-run script)))
        (set! results (.cc results name receipt))
        receipt))
    (def (submit request)
      (let* ((declaration (execution-request-request request))
             (name (execution-request-name request)))
        (unless (and (eq? (cadr declaration) 'ops) (object? (caddr declaration)))
          (error "Job Ops interpreter received a foreign request" name))
        (execute name (caddr declaration))
        ;; The next Flow receives the accumulated immutable result object.
        (make-adapter-result (list 'ops name) 'completed results #f #f)))
    (def (finalize)
      (for-each
        (lambda (name)
          (let (task (admit-task (.get job tasks) name))
            (when (hash-key? started (.get task after-start))
              (with-catch
                (lambda (failure) (set! cleanup-failures (cons (cons name failure) cleanup-failures)))
                (lambda () (execute name (.cc task 'directory workspace)))))))
        (.get projection finalizers)))
    (with-catch
      (lambda (failure) (set! primary-failure failure))
      (lambda ()
        (dynamic-wind void
          (lambda ()
            (let* ((adapter (make-runtime-adapter 'ops '(external) submit
                              unsupported-ops-operation unsupported-ops-operation unsupported-ops-operation))
                   (runner (make-runner (make-local-eager-strategy) adapter))
                   (outcome (runner-run runner (job-flow job projection workspace) (.o))))
              (set! results (run-result-value outcome))
              (set! flow-receipt-value (run-result-receipt outcome))))
          finalize)))
    (when (pair? cleanup-failures)
      (error "Funflow finalizer failed" primary-failure (reverse cleanup-failures)))
    (when primary-failure (raise primary-failure))
    (.o steps: results flow-receipt: flow-receipt-value)))
