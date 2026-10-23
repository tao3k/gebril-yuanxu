;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Production producer/publication/Context; small selected-publication inputs.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop validate element?)
        (only-in :std/io/tempfile make-temporary-file-name)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit)
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/module-system/source/selection select-module-graph)
        (only-in :yuanxu/module-system/source/build module-build-graph)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-source-ref)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!)
        (only-in :yuanxu/modules/json-schema/json-schema-source yuanxu-json-schema-read-file)
        (only-in :yuanxu/modules/json-schema/json-schema-receipt
          yuanxu-json-schema->contract-artifact
          yuanxu-json-schema-contract-artifact-normalization)
        (only-in :yuanxu/modules/json-schema/json-schema-ir yuanxu-json-schema-normalization-schema)
        (only-in :yuanxu/modules/json-schema/contracts SchemaContract.)
        (only-in "./qualification/contract-adaptation/checked-publication-test.ss"
          make-scenario make-admission allow WebContract ConfigContract ScenarioContract))
(export admission-checked-publication-test test-cleanup!)

(def completed 0)
(def (done!) (set! completed (+ completed 1)))
(def (test-cleanup!)
  (unless (= completed 7) (error "checked Core publication cases incomplete" completed))
  (displayln "CORE-CHECKED-PUBLICATION: 7 cases completed"))

(def SchemaText
  "{\"type\":\"object\",\"properties\":{\"instance_type\":{\"type\":\"string\"}},\"required\":[\"instance_type\"],\"additionalProperties\":false}")
(def (write-file path text)
  (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port))))
(def (with-inputs consume)
  (def directory (make-temporary-file-name "checked-core-publication-"))
  (create-directory directory)
  (def source (path-expand "interface.ss" directory))
  (def schema (path-expand "instance.json" directory))
  (dynamic-wind
    (lambda () (write-file source "; publication source v1\n") (write-file schema SchemaText))
    (lambda () (consume source schema))
    (lambda () (delete-file source) (delete-file schema) (delete-directory directory))))

;; Actual selection/build algorithms and AdmissionPublication context collector.
;; Only the source publication declaration is reduced to a dependency-free leaf.
;; There is no synthetic revision counter or caller-created Context object.
(def (platform source-path schema-path (policy allow))
  (def inputs (list (cons source-path (module-source-read source-path))))
  (def (current!) (module-source-admit-current! inputs))
  (def selected
    (select-module-graph
      (.o generation: "checked-source" selected: '(app/web)
          denied-modules: '() init-source: #f)
      '(app/web)
      (lambda (_id) (.o core: (.o requires: (.o)) features: (.o))) current!))
  (def build
    (module-build-graph selected
      (lambda (id)
        (.o identity: id generation: "checked-source"
            compiler-identity: 'qualification/interface
            source: (make-yuanxu-module-source-ref 'local source-path '())
            role-sources: '() source-inputs: inputs admit-current: current!))))
  (def artifact
    (yuanxu-json-schema->contract-artifact
      (yuanxu-json-schema-read-file schema-path) (list (cons 'source-ref schema-path))))
  ;; Associate the exact selected artifact with the actual value Type; there is
  ;; no automatic publication association resolver in this test or implementation.
  (def instance
    (.cc SchemaContract. identity: 'aws/instance-input
      node: (yuanxu-json-schema-normalization-schema
              (yuanxu-json-schema-contract-artifact-normalization artifact))))
  (def web-contract
    (.cc WebContract responsibilities:
      (.+ (.get WebContract responsibilities) (.o settings: instance))))
  (def config-contract
    (.cc ConfigContract responsibilities:
      (.+ (.get ConfigContract responsibilities) (.o web: web-contract))))
  (def scenario
    (.cc ScenarioContract responsibilities:
      (.+ (.get ScenarioContract responsibilities) (.o config: config-contract))))
  (defvalues (descriptor actual-contract count seen-values) (make-admission scenario policy))
  (.o publication: (.cc AdmissionPublication. graph: build schemas: (list artifact) contract: descriptor)
      admission: descriptor value-contract: actual-contract checks: count observed: seen-values))

(def (refused previous result next failure)
  (check-equal? result #f)
  (check-equal? (eq? previous next) #t)
  (check-equal? (metadata.failure? failure) #t))

(def admission-checked-publication-test
  (test-suite "Checked objects with production Core publication and Context"
    (test-case "one validation and exact references with cached parent and wrapped child"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (defvalues (parent calls raw) (make-scenario))
          (def cached (.get parent resource))
          ;; Force the parent's computed leaf before creating/admitting child,
          ;; not just construction of its lazy resource container.
          (check-equal? (.get cached instance_type) "t3.small")
          (.def (child @ parent)
            config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instance_type: "t3.medium"))))
          (defvalues (evidence next failure) (.call pub .publish parent child))
          (check-equal? failure #f)
          (check-equal? (vector-ref (.get view checks) 0) 1)
          (check-equal? (eq? next child) #f)
          (check-equal? (eq? (.get evidence candidate) next) #t)
          (check-equal? (eq? (vector-ref (.get view observed) 0) next) #t)
          (check-equal? (eq? (.get evidence admission-contract) (.get view admission)) #t)
          (check-equal? (eq? (.get view admission value-contract) (.get view value-contract)) #t)
          (check-equal? (eq? (.get evidence context) (.get pub context)) #t)
          (check-equal? (length (.get pub context schema-inputs)) 1)
          (check-equal? (pair? (.get pub context source-inputs)) #t)
          (check-equal? (.get cached instance_type) "t3.small")
          (check-equal? (.get next resource instance_type) "t3.medium")
          (check-equal? (eq? (.get next config web decorate) raw) #f)
          (check-equal? (vector-ref calls 0) 0)
          (done!))))

    (test-case "public Type validate returns normalized subject; recognition refuses invalid fields"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (defvalues (parent _calls raw) (make-scenario))
          (def checked (validate (.get view admission) parent))
          (check-equal? (eq? checked parent) #f)
          (check-equal? (eq? (.get checked config web decorate) raw) #f)
          (check-equal? (vector-ref (.get view checks) 0) 1)
          (.def (bad @ parent)
            config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instnace_type: "wrong"))))
          (check-equal? (element? (.get view admission) bad) #f)
          (check-equal? (vector-ref (.get view checks) 0) 1)
          (done!))))

    (test-case "same-name contracts and changed platform Context refuse replay"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (def other-view (platform source schema))
          (def other-pub (.get other-view publication))
          (defvalues (parent _calls _raw) (make-scenario))
          (defvalues (old next failure) (.call pub .publish parent parent))
          (check-equal? failure #f)
          (check-equal? (.get view admission identity) (.get other-view admission identity))
          (def different-contract
            (.cc pub contract: (.get other-view admission) context: (.get pub context)))
          (defvalues (bad kept refusal)
            (metadata.publish (.call different-contract .bind-evidence next)
              next (lambda (checked) (values old checked)) next))
          (refused next bad kept refusal)
          (check-equal? (metadata.failure-phase refusal) 'logic)
          (check-equal? (metadata.failure-cause refusal) #f)
          (def different-context (.cc pub context: (.get other-pub context)))
          (defvalues (bad2 kept2 refusal2)
            (metadata.publish (.call different-context .bind-evidence next)
              next (lambda (checked) (values old checked)) next))
          (refused next bad2 kept2 refusal2)
          (check-equal? (metadata.failure-phase refusal2) 'logic)
          (check-equal? (metadata.failure-cause refusal2) #f)
          (check-equal? (vector-ref (.get other-view checks) 0) 0)
          ;; A faulty custom .admit cannot smuggle the old descriptor's receipt
          ;; through the actual production publisher either.
          (def faulty (.cc (.get other-view admission) .admit: (lambda (_v _c) old)))
          (defvalues (bad3 kept3 refusal3)
            (.call (.cc other-pub contract: faulty) .publish next parent))
          (refused next bad3 kept3 refusal3)
          (done!))))

    (test-case "real source and Schema edits invalidate captured Context and existing evidence"
      (for-each
        (lambda (which)
          (with-inputs
            (lambda (source schema)
              (def view (platform source schema))
              (def pub (.get view publication))
              (defvalues (parent _calls _raw) (make-scenario))
              (defvalues (old next failure) (.call pub .publish parent parent))
              (check-equal? failure #f)
              (write-file (if (eq? which 'source) source schema)
                (if (eq? which 'source) "; publication source v2\n" (string-append SchemaText "\n")))
              (defvalues (bad kept refusal)
                (metadata.publish (.call pub .bind-evidence next)
                  next (lambda (checked) (values old checked)) next))
              (refused next bad kept refusal)
              (defvalues (bad2 kept2 refusal2) (.call pub .publish next parent))
              (refused next bad2 kept2 refusal2)
              (check-equal? (vector-ref (.get view checks) 0) 1)
              ;; Fresh platform capture uses current bytes, permitting admission.
              (def fresh (platform source schema))
              (defvalues (_receipt newer refusal3)
                (.call (.get fresh publication) .publish next parent))
              (check-equal? refusal3 #f)
              (check-equal? (.get newer resource instance_type) "t3.small"))))
        '(source schema))
      (done!))

    (test-case "source or Schema change during admission cannot replace previous value"
      (for-each
        (lambda (which)
          (with-inputs
            (lambda (source schema)
              (def view
                (platform source schema
                  (lambda (_value _context)
                    (write-file (if (eq? which 'source) source schema)
                      (if (eq? which 'source) "; changed during admission\n"
                        (string-append SchemaText "\n"))) #t)))
              (def pub (.get view publication))
              (defvalues (parent _calls _raw) (make-scenario))
              (defvalues (bad kept failure) (.call pub .publish parent parent))
              (refused parent bad kept failure)
              (check-equal? (vector-ref (.get view checks) 0) 1))))
        '(source schema))
      (done!))

    (test-case "fixed parent resource and unresolved network refuse through production publisher"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (defvalues (parent _calls _raw) (make-scenario))
          (def cached (.get parent resource))
          (.def (stale @ parent)
            config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instance_type: "t3.medium")))
            resource: cached)
          (defvalues (bad kept failure) (.call pub .publish parent stale))
          (refused parent bad kept failure)
          (.def (missing @ parent)
            config: =>.+ (.o web: =>.+ (.o network-ref: 'missing)))
          (defvalues (bad2 kept2 failure2) (.call pub .publish parent missing))
          (refused parent bad2 kept2 failure2)
          (check-equal? (vector-ref (.get view checks) 0) 2)
          (done!))))

    (test-case "stricter upstream Schema rejects fresh admission while preserving old value"
      (with-inputs
        (lambda (source schema)
          (def view (platform source schema))
          (def pub (.get view publication))
          (defvalues (parent _calls _raw) (make-scenario))
          (defvalues (old next failure) (.call pub .publish parent parent))
          (check-equal? failure #f)
          (write-file schema
            "{\"type\":\"object\",\"properties\":{\"instance_type\":{\"type\":\"string\",\"enum\":[\"t3.medium\"]}},\"required\":[\"instance_type\"],\"additionalProperties\":false}")
          (def fresh (platform source schema))
          (defvalues (bad kept refusal)
            (.call (.get fresh publication) .publish next parent))
          (refused next bad kept refusal)
          (.def (child @ parent)
            config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instance_type: "t3.medium"))))
          (defvalues (_accepted newer refusal2)
            (.call (.get fresh publication) .publish next child))
          (check-equal? refusal2 #f)
          (check-equal? (.get newer resource instance_type) "t3.medium")
          (done!))))))
