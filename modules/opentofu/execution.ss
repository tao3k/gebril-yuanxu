;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit Ops handoff over a checked publication; importing this file is inert.
(import :clan/poo/object
        (only-in :std/encoding/json write-json read-json)
        (only-in :std/string/misc string-subst)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/modules/funflow/objects Task. Job.)
        (only-in :yuanxu/modules/funflow/func run-job job-graph)
        (only-in :yuanxu/admission/publication AdmissionPublication.))
(export OpenTofuExecution. opentofu-execution)

;; POO is the public model; hashes exist only at the JSON output boundary.
(def (wire value)
  (cond ((object? value)
         (let (result (make-hash-table))
           (for-each (lambda (key)
                       (hash-put! result (symbol->string key) (wire (.ref value key))))
                     (.all-slots value))
           result))
        ;; Terraform JSON still interprets template markers in string values.
        ;; User data remains literal; generated reference expressions are separate.
        ((string? value)
         (string-subst (string-subst value "${" "$${") "%{" "%%{"))
        ((list? value) (map wire value))
        ((vector? value) (list->vector (map wire (vector->list value))))
        (else value)))

(def (json-field key value) (list->hash-table (list (cons key value))))

(def (configuration job checked local?)
  (let* ((provider (.get job provider))
         (kind (.get job resource-kind))
         (resource (.ref (.get provider types resources) kind))
         (input (.get checked resource))
         (fields (wire input))
         (prefix (.get job provider-name))
         (name (.get job resource-name)))
    ;; Only this bounded local example may attach an executable provisioner.
    ;; printf receives message as data, never a shell program.
    (when local?
      (unless (and (eq? kind 'null_resource) (eq? prefix 'null))
        (error "local execution only supports null_resource"))
      (hash-put! fields "provisioner"
        (list (hash ("local-exec"
          (hash ("command" (wire (.get input triggers message)))
                ("interpreter" '("printf" "%s\n"))))))))
    (let (result
      (hash ("terraform" (hash ("required_providers"
              (json-field (symbol->string prefix)
                (hash ("source" (.get resource provider))
                      ("version" (.get resource version)))))))
            ("resource" (json-field (symbol->string kind) (json-field name fields)))))
      (unless local?
        (hash-put! result "provider"
          (json-field (symbol->string prefix) (wire (.get job provider-config)))))
      (when local?
        (hash-put! result "output"
          (hash ("message" (hash ("value"
            (string-append "${null_resource." name ".triggers.message}")))))))
      result)))

;; Task interpretation remains the existing Ops process boundary. The guards
;; protect each forward effect; cleanup uses the previously admitted command
;; even when Schema/source freshness was lost after apply started.
(def (run-opentofu-task task)
  (when (.get task guard-current?) ((.get task owner publication context admit-current)))
  (let (result (run-script task))
    (when (.get task guard-current?) ((.get task owner publication context admit-current)))
    result))
(.def (OpenTofuTask. task [Task.])
  owner: #f arguments: '() guard-current?: #t
  command: (append (.get owner command) arguments)
  timeout: (.get owner timeout)
  environment: (.+ (.o TF_IN_AUTOMATION: "1" CHECKPOINT_DISABLE: "1") (.get owner environment))
  .run: (lambda () (run-opentofu-task task)))
(def (execution-task owner-value arguments-value dependencies)
  (.cc OpenTofuTask. 'owner owner-value 'arguments arguments-value 'needs dependencies))

(.def (OpenTofuExecution. execution [Job.])
  name: 'opentofu
  publication: #f previous: (.o)
  command: '() timeout: 20 environment: (.o)
  provider: #f provider-name: #f provider-config: (.o)
  resource-kind: #f resource-name: "example"
  selected: (if (eq? provider-name 'null) '(output) '(validate))
  finalizers: (if (eq? provider-name 'null) '(destroy) '())
  tasks:
  (.o init: (execution-task execution '("init" "-backend=false" "-input=false" "-no-color") '())
      validate: (execution-task execution '("validate" "-no-color") '(init))
      plan: (execution-task execution '("plan" "-input=false" "-no-color" "-out=hello.tfplan") '(validate))
      apply: (execution-task execution '("apply" "-input=false" "-no-color" "hello.tfplan") '(plan))
      output: (execution-task execution '("output" "-json" "message") '(apply))
      destroy: (.cc (execution-task execution '("destroy" "-auto-approve" "-input=false" "-no-color") '())
                 'after-start 'apply 'guard-current? #f))
  .run: (lambda (workspace) (run-execution execution workspace)))

(def (run-execution job work-directory)
  (def publication (.get job publication))
  (unless publication (error "selected publication must be bound before execution"))
  (let (baseline (.get publication value))
    (unless (and (eq? (.get job provider) (.get baseline provider))
                 (eq? (.get job resource-kind) (.get baseline resource-kind))
                 (eq? (.get job provider-name) (.get baseline provider-name)))
      (error "execution provider must match the selected publication")))
  (defvalues (admission-evidence checked failure)
    (.call publication .publish (.get job previous) job))
  (when failure (error "OpenTofu input admission refused" failure))
  (def local? (eq? (.get checked provider-name) 'null))
  (def projection (job-graph checked))
  ;; This AWS example performs configuration validation, never plan or apply.
  (unless (or local? (every (cut memq <> '(init validate)) (.get projection order)))
    (error "AWS example only permits init and validate"))
  (def document (configuration checked checked local?))
  (unless (and (string? work-directory) (file-exists? work-directory)
               (pair? (.get checked command)))
    (error "execution requires an existing workspace and selected OpenTofu command"))
  (unless (null? (directory-files work-directory))
    (error "OpenTofu example workspace must be empty" work-directory))
  ((.get publication context admit-current))
  (call-with-output-file (path-expand "main.tf.json" work-directory)
    (lambda (port) (write-json port document)))
  (def outcome (run-job checked work-directory))
  ((.get publication context admit-current))
  (def final-steps (.get outcome steps))
  (def output-value
    (and local? (.slot? final-steps 'output)
      (call-with-input-string (.get final-steps output output) read-json)))
  (.o kind: (if local? 'local-execution-completed 'configuration-validated)
      value: checked evidence: admission-evidence steps: final-steps
      graph: projection flow-receipt: (.get outcome flow-receipt) output: output-value))

;; Existing platform binding: workspaces are supplied only to Job.run.
(def (opentofu-execution selection owner name command)
  (let (publication (.call AdmissionPublication. .for-export selection owner name))
    (.cc (.get publication value) 'publication publication 'command command)))
