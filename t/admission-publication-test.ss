;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile make-temporary-file-name)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :core/types PooFlowContract. poo-flow-classification-evidence)
        (only-in :core/admission/publication AdmissionPublication.)
        (only-in :core/module-system/source/selection select-module-graph)
        (only-in :core/module-system/source/build module-build-graph)
        (only-in :core/module-system/source/objects make-poo-flow-module-source-ref)
        (only-in :core/module-system/source/admission module-source-read module-source-admit-current!)
        (only-in :core/module-system/source/admission current-module-source-observer)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/modules/json-schema/json-schema-source poo-flow-json-schema-read-file)
        (only-in :core/modules/json-schema/json-schema-receipt
          poo-flow-json-schema->contract-artifact
          poo-flow-json-schema-contract-artifact-normalization)
        (only-in :core/modules/json-schema/json-schema-ir poo-flow-json-schema-normalization-schema)
        :core/modules/json-schema/contracts
        (only-in :clan/poo/object-contract diagnose))
(export admission-publication-test)

(def SchemaText
  "{\"type\":\"object\",\"properties\":{\"port\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":65535}},\"required\":[\"port\"],\"additionalProperties\":false}")
(def (write-file path text)
  (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port))))
(def (with-inputs test)
  (def directory (make-temporary-file-name "admission-publication-"))
  (create-directory directory)
  (def source (path-expand "interface.ss" directory))
  (def schema (path-expand "server.json" directory))
  (dynamic-wind
    (lambda () (write-file source "; selected source v1\n") (write-file schema SchemaText))
    (lambda () (test source schema))
    (lambda () (delete-file source) (delete-file schema) (delete-directory directory))))

;; Actual resolver/build-Graph algorithms; preparation and generation capability
;; are bounded fixtures. No runtime Loader or deferred module link is invoked.
(def (platform source-path schema-path)
  (def revision 1)
  (def (current!) (unless (= revision 1) (error "selected Graph replaced")))
  (def sources (list (cons source-path (module-source-read source-path))))
  (def graph-context (.o generation: "graph-1" selected: '(app/web)
                        denied-modules: '() init-source: #f))
  (def selected
    (select-module-graph graph-context '(app/web)
      (lambda (_id) (.o core: (.o requires: (.o)) features: (.o))) current!))
  (def build
    (module-build-graph selected
      (lambda (id)
        (.o identity: id generation: "graph-1"
            compiler-identity: 'fixture/interface
            source: (make-poo-flow-module-source-ref 'local source-path '())
            role-sources: '() source-inputs: sources
            admit-current: (lambda () (current!) (module-source-admit-current! sources))))))
  (def artifact
    (poo-flow-json-schema->contract-artifact
      (poo-flow-json-schema-read-file schema-path) (list (cons 'source-ref schema-path))))
  (def value-contract
    (.cc SchemaContract. identity: 'test/server
      node: (poo-flow-json-schema-normalization-schema
              (poo-flow-json-schema-contract-artifact-normalization artifact))))
  (def projection (.cc ProjectionContract. constraint: value-contract
                      project: (lambda (value) (.get value config))))
  (def descriptor
    (.cc PooFlowContract. identity: 'test/application
      .classify:
      (lambda (value context-value)
        (let (issues (diagnose projection value))
          (poo-flow-classification-evidence
            'test/application value (null? issues) issues context-value)))))
  (.o publication: (.cc AdmissionPublication. graph: build schemas: (list artifact) contract: descriptor)
      admission: descriptor replace-graph!: (lambda () (set! revision 2))))

(.def (Parent @ [] config)
  config: (.o port: 80)
  resource: (.o port: (.get config port)))
(.def (Release @ Parent) config: =>.+ (.o port: 443))

(def (check-refused publisher phase (inner-phase #f))
  (defvalues (result next failure) (.call publisher .publish Parent Release))
  (check-equal? result #f)
  (check-equal? (eq? next Parent) #t)
  (check-equal? (metadata.failure? failure) #t)
  (check-equal? (metadata.failure-phase failure) phase)
  ;; Checked-subject binding runs inside the source callback. The standard
  ;; publication wrapper preserves its original output/logic refusal as cause.
  (when inner-phase
    (check-equal? (metadata.failure? (metadata.failure-cause failure)) #t)
    (check-equal? (metadata.failure-phase (metadata.failure-cause failure)) inner-phase)))

(def admission-publication-test
  (test-suite "Platform admission context and publication currentness"
    (poo-flow-test-case "one Context source window reads once; an independent window observes edits"
      (with-inputs
        (lambda (source schema)
          (def pub (.get (platform source schema) publication))
          (def context (.get pub context))
          (def reads (make-hash-table))
          (parameterize ((current-module-source-observer
                          (lambda (kind amount)
                            (when (and (pair? kind) (eq? (car kind) 'file-read))
                              (hash-update! reads (caddr kind) (cut + <> amount) 0)))))
            ((.get context admit-current)))
          (check-equal? (hash-ref reads source) 1)
          (check-equal? (hash-ref reads schema) 1)
          (write-file schema (string-append SchemaText "\n"))
          (check-refused pub 'source))))
    (test-case "package guard failure before or after admission preserves previous value"
      (for-each
        (lambda (fail-at)
          (with-inputs
            (lambda (source schema)
              (def checks 0)
              (def pub
                (.cc (.get (platform source schema) publication)
                  package-current:
                  (lambda ()
                    (set! checks (+ checks 1))
                    (when (= checks fail-at) (error "package changed")))))
              (check-refused pub 'source)
              (check-equal? checks fail-at))))
        '(1 2)))
    (test-case "platform generates context and publishes final child after parent cache"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (check-equal? (.get Parent resource port) 80)
          (defvalues (receipt next failure) (.call pub .publish Parent Release))
          (check-equal? failure #f)
          (check-equal? (eq? next Release) #t)
          (check-equal? (.get (.get receipt candidate) resource port) 443)
          (check-equal? (eq? (.get receipt context) (.get pub context)) #t)
          (check-equal? (length (.get pub context schema-inputs)) 1)
          (check-equal? (pair? (.get pub context source-inputs)) #t))))

    (test-case "source and Schema edits after context demand refuse before admission"
      (for-each
        (lambda (which)
          (with-inputs
            (lambda (source schema)
              (def view (platform source schema))
              (def pub (.get view publication))
              (def captured (.get pub context))
              (write-file (if (eq? which 'source) source schema)
                          (if (eq? which 'source) "; source v2\n" (string-append SchemaText "\n")))
              (check-refused pub 'source))))
        '(source schema)))

    (test-case "source and Schema edits DURING admission refuse at publication"
      (for-each
        (lambda (which)
          (with-inputs
            (lambda (source schema)
              (def view (platform source schema))
              (def pub (.get view publication))
              ;; Effectful obligation is a test fault injector, not authoring API.
              (def descriptor
                (.cc (.get view admission) .obligations:
                  (lambda (_value _context)
                    (write-file (if (eq? which 'source) source schema)
                                (if (eq? which 'source) "; source v2\n" (string-append SchemaText "\n")))
                    '())))
              (check-refused (.cc pub contract: descriptor) 'source 'logic))))
        '(source schema)))

    (test-case "selected Graph replacement during admission refuses publication"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def descriptor
            (.cc (.get view admission) .obligations:
              (lambda (_value _context) ((.get view replace-graph!)) '())))
          (check-refused (.cc (.get view publication) contract: descriptor) 'source 'logic))))

    (test-case "old accepted receipt from another platform context cannot be replayed"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (defvalues (old _next _failure) (.call pub .publish Parent Parent))
          (def fresh (.cc pub))
          (check-equal? (eq? (.get fresh context) (.get old context)) #f)
          (def replay (.cc (.get view admission) .admit: (lambda (_value _context) old)))
          (check-refused (.cc fresh contract: replay) 'source 'logic))))

    (test-case "new platform snapshot permits fresh admission after an upstream source update"
      (with-inputs
        (lambda (source schema)
          (def old-view (platform source schema))
          (def pub (.get old-view publication))
          (def captured (.get pub context))
          (write-file source "; selected source v2\n")
          (check-refused pub 'source)
          (def new-view (platform source schema))
          (defvalues (receipt next failure)
            (.call (.get new-view publication) .publish Parent Release))
          (check-equal? failure #f)
          (check-equal? (eq? next Release) #t)
          (check-equal? (eq? captured (.get receipt context)) #f))))

    (test-case "a stricter upstream Schema invalidates the old view and rejects the old candidate"
      (with-inputs
        (lambda (source schema)
          (def old-view (platform source schema))
          (def old-pub (.get old-view publication))
          (def captured (.get old-pub context))
          (write-file schema
            "{\"type\":\"object\",\"properties\":{\"port\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}},\"required\":[\"port\"],\"additionalProperties\":false}")
          (check-refused old-pub 'source)
          (def fresh (platform source schema))
          (check-refused (.get fresh publication) 'source 'output)
          (defvalues (receipt next failure) (.call (.get fresh publication) .publish Parent Parent))
          (check-equal? failure #f)
          (check-equal? (eq? next Parent) #t)
          (check-equal? (.get (.get receipt candidate) resource port) 80))))

    (test-case "artifact cannot claim a different current Schema source"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          ;; Valid JSON but a different schema, before initial context capture.
          (write-file schema "{\"type\":\"string\"}")
          (check-exception (.get pub context) error?))))))
