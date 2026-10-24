;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/error Error? Error-message)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence
                 yuanxu-predicate-contract yuanxu-contract-admit
                 yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/module-system/source/selection select-module-graph)
        (only-in :yuanxu/module-system/source/build module-build-graph)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-source-ref)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/modules/json-schema/json-schema-source yuanxu-json-schema-read-file)
        (only-in :yuanxu/modules/json-schema/json-schema-receipt
          yuanxu-json-schema->contract-artifact
          yuanxu-json-schema-contract-artifact-normalization)
        (only-in :yuanxu/modules/json-schema/json-schema-ir yuanxu-json-schema-normalization-schema)
        :yuanxu/modules/json-schema/contracts
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
            source: (make-yuanxu-module-source-ref 'local source-path '())
            role-sources: '() source-inputs: sources
            admit-current: (lambda () (current!) (module-source-admit-current! sources))))))
  (def artifact
    (yuanxu-json-schema->contract-artifact
      (yuanxu-json-schema-read-file schema-path) (list (cons 'source-ref schema-path))))
  (def value-contract
    (.cc SchemaContract. identity: 'test/server
      node: (yuanxu-json-schema-normalization-schema
              (yuanxu-json-schema-contract-artifact-normalization artifact))))
  (def projection (.cc ProjectionContract. constraint: value-contract
                      project: (lambda (value) (.get value config))))
  (def descriptor
    (.cc YuanxuContract. identity: 'test/application
      .classify:
      (lambda (value context-value)
        (let (issues (diagnose projection value))
          (yuanxu-classification-evidence
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

;; A source-only selected publication exercises the real .for-export assembler
;; without Nix. Only the Schema getter below is an optional fault injector.
(def (assembly-selection source-path schema-path (during-schema void) (refine-descriptor values) (refine-publication values))
  (def inputs (list (cons source-path (module-source-read source-path))))
  (def (current!) (module-source-admit-current! inputs "assembly source changed"))
  (def artifact
    (yuanxu-json-schema->contract-artifact
      (yuanxu-json-schema-read-file schema-path) (list (cons 'source-ref schema-path))))
  (def fields
    (.o (:: @ SchemaContract.)
      identity: 'assembly/fields
      node: (yuanxu-json-schema-normalization-schema
              (yuanxu-json-schema-contract-artifact-normalization artifact))
      schema-artifact: (begin (during-schema) artifact)
      schema: (yuanxu-json-schema-read-file schema-path)
      source-inputs: (list (cons schema-path (module-source-read schema-path)))))
  (def descriptor
    (refine-descriptor
      (.cc YuanxuContract. identity: 'assembly/application
        value-contract: (.cc ProjectionContract. constraint: fields
                         project: (lambda (value) (.get value config))))))
  (def module-publication
    (refine-publication
      (.o identity: 'app/web features: (.o)
        core: (.o requires: (.o)
                admissions: (.o Scenario: (.o contract-path: '(types Application)
                                             export-path: '(value)))))))
  (def selected
    (select-module-graph
      (.o generation: "assembly-1" selected: '(app/web)
          denied-modules: '() init-source: #f)
      '(app/web) (lambda (_owner) module-publication) current!))
  (def graph
    (module-build-graph selected
      (lambda (owner)
        (.o identity: owner generation: "assembly-1"
            compiler-identity: 'fixture/interface
            source: (make-yuanxu-module-source-ref 'local source-path '())
            role-sources: '() source-inputs: inputs admit-current: current!))))
  (.o build-graph: graph selected-graph: selected package-current: #f
      sources-current: current!
      .selected-record:
      (lambda (_owner)
        (.o publication: module-publication
            scope: (.o types: (.o Application: descriptor) value: Parent)))))

(def admission-publication-test
  (test-suite "Platform admission context and publication currentness"
    (yuanxu-test-case "selected assembly has one final Context check; standalone construction retains its own"
      (with-inputs
        (lambda (source schema)
          (def selection (assembly-selection source schema))
          ;; Bound the work counter to Context assembly, not the first lazy
          ;; source projection. Schema getters remain cold in this control.
          (.get selection build-graph source-inputs)
          (def standalone (.get (platform source schema) publication))
          (def reads 0)
          (def physical 0)
          (def (observe key amount)
            (when (equal? key (list 'file-read 'build-admit-before source))
              (set! reads (+ reads amount)))
            (when (and (pair? key) (eq? (car key) 'file-read)
                       (equal? (caddr key) source))
              (set! physical (+ physical amount))))
          (def bound
            (parameterize ((current-module-source-observer observe))
              (.call AdmissionPublication. .for-export selection 'app/web 'Scenario)))
          ;; Complete export entry and contribution-bound return. The private
          ;; source-only entry is counted under build-current, not before.
          ;; Count every phase too: the cached, route-free index has no extra
          ;; source traversal. This is fewer physical opens, not just
          ;; a transfer from the before label to compiler-current.
          (check-equal? (list reads physical) '(2 4))
          (check-equal? (eq? (.get bound context selected-graph)
                            (.get selection selected-graph)) #t)
          (check-equal? (length (.get bound context schema-inputs)) 1)
          (set! reads 0)
          (parameterize ((current-module-source-observer observe))
            (.get standalone context))
          (check-equal? reads 2))))
    (yuanxu-test-case "a cold contribution declaration still requires source admission before its getter"
      (with-inputs
        (lambda (source schema)
          (def demanded 0)
          (def selection
            (assembly-selection source schema void values
              (lambda (baseline)
                (let (core (.get baseline core))
                  (.cc baseline core:
                    (.o (:: @ core)
                      contributions: (begin (set! demanded (+ demanded 1)) (.o))))))))
          (def refusal
            (with-catch values
              (lambda ()
                (.call AdmissionPublication. .for-export
                  (.cc selection sources-current:
                    (lambda () (error "route source changed")))
                  'app/web 'Scenario))))
          (check-equal? demanded 0)
          (check-equal? (Error? refusal) #t)
          (check-equal? (Error-message refusal) "route source changed"))))
    (yuanxu-test-case "a route-free index is not authority after its Core changes"
      (with-inputs
        (lambda (source schema)
          (def selection (assembly-selection source schema))
          (def bound (.call AdmissionPublication. .for-export selection 'app/web 'Scenario))
          (def node (car (.get selection selected-graph nodes)))
          (def core (.get node publication core))
          (.putslot! core 'contributions ($constant-slot-spec (.o)))
          (check-exception ((.get bound context admit-current))
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception) "contribution object changed")))))))
    (yuanxu-test-case "route-free indexing still checks sources before a cold Contract handler"
      (with-inputs
        (lambda (source schema)
          (def handlers 0)
          (def selection
            (assembly-selection source schema void
              (lambda (base)
                (.o (:: @ base)
                  .contribution-obligations:
                  (begin (set! handlers (+ handlers 1))
                         (lambda (_candidate _rows _context) '()))))))
          (def guarded
            (.o (:: @ selection)
              .selected-record:
              (lambda (owner)
                (def record (.call selection .selected-record owner))
                (def scope (.get record scope))
                (.cc record scope:
                  (.o (:: @ scope)
                    value: (begin (write-file source "; changed resolving export\n") Parent))))))
          (def refusal
            (with-catch values
              (cut .call AdmissionPublication. .for-export guarded 'app/web 'Scenario)))
          (check-equal? handlers 0)
          (check-equal? (Error? refusal) #t)
          (check-equal? (Error-message refusal) "assembly source changed"))))
    (yuanxu-test-case "the enclosing assembly check refuses changes made while resolving Schema metadata"
      (with-inputs
        (lambda (source schema)
          (def selection
            (assembly-selection source schema
              (lambda () (write-file source "; changed during Schema association\n"))))
          (check-exception
            (.call AdmissionPublication. .for-export selection 'app/web 'Scenario)
            (lambda (exception)
              (and (Error? exception)
                   (string=? (Error-message exception) "assembly source changed")))))))
    (yuanxu-test-case "selected Context source collection cannot bypass entry or final request policy"
      (for-each
        (lambda (refuse-at)
          (with-inputs
            (lambda (source schema)
              (def requests 0)
              (def schemas 0)
              (def selection
                (assembly-selection source schema (lambda () (set! schemas (+ schemas 1)))))
              ;; A replaceable request is a deliberate negative injector. It is
              ;; still called by the complete export entry and bound return.
              (def guarded
                (.cc (.get selection build-graph)
                  external-packages:
                  (list (.o source-inputs: '()
                          admit-current:
                          (lambda ()
                            (set! requests (+ requests 1))
                            (when (= requests refuse-at)
                              (error "assembly request policy rejected")))))))
              (check-exception
                (.call AdmissionPublication. .for-export
                  (.cc selection build-graph: guarded) 'app/web 'Scenario)
                (lambda (exception)
                  (and (Error? exception)
                       (string=? (Error-message exception) "assembly request policy rejected"))))
              (check-equal? requests refuse-at)
              (check-equal? schemas (if (= refuse-at 1) 0 1)))))
        '(1 2)))
    (yuanxu-test-case "intermediate source collection checks request inputs before cold Schema getters"
      (with-inputs
        (lambda (source schema)
          (def schemas 0)
          (def observations (list (cons schema (module-source-read schema))))
          (def selection
            (assembly-selection source schema
              (lambda () (set! schemas (+ schemas 1)))
              (lambda (base)
                ;; Fault injection occurs after export's complete entry check,
                ;; while reading the descriptor's configuration observations.
                (.o (:: @ base)
                  source-inputs:
                  (begin (write-file schema (string-append SchemaText "\n")) '())))))
          (def guarded
            (.cc (.get selection build-graph)
              external-packages:
              (list (.o source-inputs: observations
                      admit-current:
                      (lambda ()
                        (module-source-admit-current! observations "request input changed"))))))
          (def failure
            (with-catch values
              (lambda ()
                (.call AdmissionPublication. .for-export
                  (.cc selection build-graph: guarded) 'app/web 'Scenario))))
          (check-equal? schemas 0)
          (check-equal? (Error? failure) #t)
          (check-equal? (Error-message failure) "admission source input changed"))))
    (yuanxu-test-case "no package callback means no second pre-admission boundary"
      (with-inputs
        (lambda (source schema)
          (def pub (.get (platform source schema) publication))
          (def stages '())
          (def observer
            (lambda (key _amount)
              (when (and (pair? key) (eq? (car key) 'admission-stage-start))
                (set! stages (cons (cadr key) stages)))))
          (defvalues (_receipt next failure)
            (parameterize ((current-module-source-observer observer))
              (.call pub .publish Parent Release)))
          (check-equal? failure #f)
          (check-equal? (eq? next Release) #t)
          (check-equal? (and (memq 'entry-current stages) #t) #t)
          (check-equal? (memq 'post-package-current stages) #f)
          ;; A real package callback is an open boundary even if its current
          ;; implementation does no work. Its post-check must still execute.
          (set! stages '())
          (def with-package (.cc pub package-current: void))
          (defvalues (_second _value second-failure)
            (parameterize ((current-module-source-observer observer))
              (.call with-package .publish Parent Release)))
          (check-equal? second-failure #f)
          (check-equal? (and (memq 'post-package-current stages) #t) #t)
          ;; Source mutation in admission cannot use the entry check as an
          ;; approval. Final meaning-current still refuses and retains Parent.
          (def changed
            (.cc pub contract:
              (.cc (.get pub contract)
                .obligations:
                (lambda (_candidate _context)
                  (write-file schema (string-append SchemaText "\n")) '()))))
          (check-refused changed 'source 'logic))))
    (yuanxu-test-case "publication owns child analysis but not admissions inside obligations"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def double-admit? #f)
          (def child-base (yuanxu-predicate-contract 'test/child object? (lambda (_v _c) '())))
          (.def (Child @ child-base)
            (.admit (inherited)
              (lambda (candidate context)
                (def first ((inherited) candidate context))
                (if double-admit? ((inherited) candidate context) first))))
          (def child Child)
          (def other (yuanxu-predicate-contract 'test/independent object? (lambda (_v _c) '())))
          (def descriptor
            (.cc (.get view admission) responsibilities: (.o config: child)
              .obligations:
              (lambda (candidate context)
                (unless (yuanxu-validation-evidence-accepted?
                          (yuanxu-contract-admit other (.get candidate config) context))
                  (error "independent admission refused"))
                '())))
          (def publisher (.cc (.get view publication) contract: descriptor))
          (def base (.get publisher context))
          (def full-child 0)
          (def full-root 0)
          (def independent 0)
          (def analytic-child 0)
          (def reject-child? #f)
          ;; Test policy callbacks; the Graph, producer, binding and publisher
          ;; remain real. Child analysis is not permission for an arbitrary call.
          (.def (Context @ base)
            .contract-obligations:
            (lambda (actual _candidate)
              (cond ((eq? actual child) (set! full-child (+ full-child 1)))
                    ((eq? actual other) (set! independent (+ independent 1)))
                    ((eq? actual descriptor) (set! full-root (+ full-root 1))))
              ((.get base admit-current))
              '())
            .responsibility-obligations:
            (lambda (actual _candidate)
              (unless (eq? actual child) (error "analysis escaped its responsibility edge"))
              (set! analytic-child (+ analytic-child 1))
              (if reject-child? (list (.o kind: 'test-child-refused)) '())))
          (def target (.cc publisher context: Context))
          (defvalues (receipt next failure) (.call target .publish Parent Release))
          (check-equal? failure #f)
          (check-equal? (eq? next Release) #t)
          (check-equal? analytic-child 1)
          (check-equal? full-child 0)
          (check-equal? full-root 1)
          (check-equal? independent 1)
          (def evidence (car (.get receipt responsibility-evidence)))
          (check-equal? (eq? (.get evidence admission-contract) child) #t)
          (check-equal? (eq? (.get evidence candidate) (.get next config)) #t)
          ;; An override's second inherited producer call has no remaining
          ;; role edge. It must perform the full child Context callback.
          (set! double-admit? #t)
          (defvalues (_second _next second-failure) (.call target .publish Parent Release))
          (check-equal? second-failure #f)
          (check-equal? analytic-child 2)
          (check-equal? full-child 1)
          (check-equal? full-root 2)
          (check-equal? independent 2)
          (set! double-admit? #f)
          (set! reject-child? #t)
          (check-refused target 'source 'output)
          (check-equal? analytic-child 3)
          (check-equal? independent 2))))
    (yuanxu-test-case "one Context source window reads once; an independent window observes edits"
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

    (test-case "rejected evidence keeps the old value without a post-admission package effect"
      (with-inputs
        (lambda (source schema)
          (def checks 0)
          (def view (platform source schema))
          (def pub
            (.cc (.get view publication)
              package-current: (lambda () (set! checks (+ checks 1)))
              contract:
              (.cc (.get view admission)
                .obligations:
                (lambda (_candidate _context) (list (.o kind: 'test-refused))))))
          ;; The standard public invocation reports the same nested output
          ;; refusal; this is not a new rejection protocol or a cached acceptance.
          (check-refused pub 'source 'output)
          (check-equal? checks 1))))

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
