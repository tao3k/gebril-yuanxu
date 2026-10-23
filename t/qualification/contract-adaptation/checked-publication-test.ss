;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolated integration fixture: public validation, real Core producer and
;;; public publication. No module association resolver or runtime Loader.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop validate Fun TypeError?)
        (only-in :clan/poo/type String Symbol)
        :clan/poo/object-contract
        (prefix-in :clan/poo/declarative-metadata metadata.)
        :yuanxu/modules/json-schema/contracts
        (only-in :yuanxu/admission/publication AdmissionPublication.)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence))
(export checked-publication-test test-cleanup!
        make-scenario make-admission allow
        WebContract ConfigContract ScenarioContract)

(def completed-cases 0)
(def (completed!) (set! completed-cases (+ 1 completed-cases)))
(def (test-cleanup!)
  (unless (= completed-cases 8)
    (error "checked publication cases were skipped or incomplete" completed-cases))
  (displayln "CHECKED-PUBLICATION: 8 cases completed"))

;; AWS-shaped field fixture, not a real provider export or deployment.
(def InstanceInput
  (schema-value-contract 'aws/instance-input
    '((type . "object")
      (properties . ((instance_type . ((type . "string")))))
      (required . ("instance_type")) (additionalProperties . #f))))
(def NetworkContract
  (.cc ObjectContract. responsibilities: (.o id: Symbol)))
(def WebContract
  (.cc ObjectContract. responsibilities:
    (.o network-ref: Symbol settings: InstanceInput
        decorate: (Fun String <- String))))
(def ConfigContract
  (refine
    (.cc ObjectContract. responsibilities:
      (.o network: NetworkContract web: WebContract))
    (lambda (value path)
      (if (eq? (.get value network id) (.get value web network-ref)) '()
        (list (.o kind: 'unresolved-network path: (append path '(web network-ref))))))))
(def ResourceContract
  (.cc ObjectContract. responsibilities:
    (.o instance_type: String network: Symbol)))
(def ScenarioContract
  (refine
    (.cc ObjectContract. responsibilities:
      (.o config: ConfigContract resource: ResourceContract))
    (lambda (value path)
      (if (and (equal? (.get value resource instance_type)
                       (.get value config web settings instance_type))
               (eq? (.get value resource network)
                    (.get value config web network-ref))) '()
        (list (.o kind: 'stale-resource-projection path: (append path '(resource))))))))

(def (make-scenario)
  (def calls (vector 0))
  (def raw-function
    (lambda (text) (vector-set! calls 0 (+ 1 (vector-ref calls 0))) text))
  (.def (parent @ [] config)
    config:
    (.o network: (.o id: 'private)
        web: (.o network-ref: 'private
                 settings: (.o instance_type: "t3.small")
                 decorate: raw-function))
    resource:
    (.o instance_type: (.get config web settings instance_type)
        network: (.get config web network-ref)))
  (values parent calls raw-function))

(def (make-context revision)
  (def captured (vector-ref revision 0))
  (.o generation: captured
      admit-current:
      (lambda ()
        (unless (= captured (vector-ref revision 0))
          (error "fixture source or Schema revision changed")))))

;; Count root validation invocations, not every nested field diagnostic.
;; Policy predicates are test inputs; the evidence producer is actual Core code.
(def (make-admission value-contract-value policy)
  (def count (vector 0))
  (def observed (vector #f))
  (.def (watched @ value-contract-value)
    (.validate =>
      (lambda (previous)
        (lambda (candidate)
          (vector-set! count 0 (+ 1 (vector-ref count 0)))
          (previous candidate)))))
  (.def (descriptor @ YuanxuContract.)
    identity: 'aws/scenario-admission
    value-contract: watched
    .classify:
    (lambda (candidate context)
      (vector-set! observed 0 candidate)
      (def accepted (policy candidate context))
      (yuanxu-classification-evidence 'aws/context candidate accepted
        (if accepted '() (list (.o kind: 'policy-refused))) context)))
  (values descriptor watched count observed))

(def (publish-checked previous candidate descriptor context-value)
  ;; Synthetic field/Context data still belongs to this fixture. The protocol,
  ;; normalization and evidence binding belong to the production publisher.
  (.call (.cc AdmissionPublication. contract: descriptor context: context-value)
    .publish previous candidate))
(def (check-refused previous result next refusal)
  (check-equal? result #f)
  (check-equal? (eq? previous next) #t)
  (check-equal? (metadata.failure? refusal) #t))
(def (allow _candidate _context) #t)

(def checked-publication-test
  (test-suite "Checked value through Core admission and public publication"
    (test-case "one normalization preserves actual descriptor and wrapped root"
      (defvalues (parent calls raw) (make-scenario))
      (defvalues (descriptor actual-contract count observed)
        (make-admission ScenarioContract allow))
      (def context (make-context (vector 0)))
      (defvalues (evidence next refusal) (publish-checked parent parent descriptor context))
      (check-equal? refusal #f)
      (check-equal? (vector-ref count 0) 1)
      (check-equal? (eq? (.get descriptor value-contract) actual-contract) #t)
      (check-equal? (eq? (.get evidence admission-contract) descriptor) #t)
      (check-equal? (eq? (.get evidence context) context) #t)
      (check-equal? (eq? (.get evidence candidate) next) #t)
      (check-equal? (eq? (vector-ref observed 0) next) #t)
      (check-equal? (eq? parent next) #f)
      (check-equal? (eq? (.get next config web decorate) raw) #f)
      (check-equal? (vector-ref calls 0) 0)
      (check-exception ((.get next config web decorate) 7) TypeError?)
      (check-equal? (vector-ref calls 0) 0)
      (check-equal? ((.get next config web decorate) "web") "web")
      (check-equal? (vector-ref calls 0) 1)
      (check-equal? (vector-ref count 0) 1)
      (completed!))

    (test-case "parent cached projection does not freeze final child"
      (defvalues (parent _calls _raw) (make-scenario))
      (def cached (.get parent resource))
      (defvalues (descriptor _contract count _seen) (make-admission ScenarioContract allow))
      (def context (make-context (vector 0)))
      (defvalues (old old-next old-refusal) (publish-checked parent parent descriptor context))
      (check-equal? old-refusal #f)
      (.def (child @ parent)
        config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instance_type: "t3.medium"))))
      (defvalues (evidence next refusal) (publish-checked old-next child descriptor context))
      (check-equal? refusal #f)
      (check-equal? (.get cached instance_type) "t3.small")
      (check-equal? (.get next resource instance_type) "t3.medium")
      (check-equal? (.get next config web settings instance_type) "t3.medium")
      (def publication (.cc AdmissionPublication. contract: descriptor context: context))
      (defvalues (bad kept failure)
        (metadata.publish (.call publication .bind-evidence next)
          old-next (lambda (checked) (values old checked)) next))
      (check-refused old-next bad kept failure)
      (check-equal? (metadata.failure-phase failure) 'logic)
      (check-equal? (vector-ref count 0) 2)
      (completed!))

    (test-case "same named different actual contracts reject old evidence"
      (defvalues (parent _calls _raw) (make-scenario))
      (defvalues (first first-contract first-count _seen) (make-admission ScenarioContract allow))
      (defvalues (second second-contract second-count _seen2)
        (make-admission (.cc ScenarioContract) allow))
      (def context (make-context (vector 0)))
      (defvalues (old next refusal) (publish-checked parent parent first context))
      (check-equal? refusal #f)
      (check-equal? (.get first identity) (.get second identity))
      (check-equal? (.get first-contract identity) (.get second-contract identity))
      (check-equal? (eq? first-contract second-contract) #f)
      (def publication (.cc AdmissionPublication. contract: second context: context))
      (defvalues (bad kept failure)
        (metadata.publish (.call publication .bind-evidence next)
          parent (lambda (checked) (values old checked)) next))
      (check-refused parent bad kept failure)
      (check-equal? (vector-ref second-count 0) 0)
      (defvalues (fresh newer failure2) (publish-checked next parent second context))
      (check-equal? failure2 #f)
      (check-equal? (eq? (.get fresh admission-contract) second) #t)
      (check-equal? (eq? (.get fresh candidate) newer) #t)
      (check-equal? (vector-ref second-count 0) 1)
      (completed!))

    (test-case "equal looking fresh context rejects old evidence"
      (defvalues (parent _calls _raw) (make-scenario))
      (defvalues (descriptor _contract count _seen) (make-admission ScenarioContract allow))
      (def context (make-context (vector 0)))
      (def other (.cc context))
      (defvalues (old next refusal) (publish-checked parent parent descriptor context))
      (check-equal? refusal #f)
      (def publication (.cc AdmissionPublication. contract: descriptor context: other))
      (defvalues (bad kept failure)
        (metadata.publish (.call publication .bind-evidence next)
          parent (lambda (checked) (values old checked)) next))
      (check-refused parent bad kept failure)
      (check-equal? (metadata.failure-phase failure) 'logic)
      (check-equal? (vector-ref count 0) 1)
      (defvalues (fresh _newer failure2) (publish-checked next parent descriptor other))
      (check-equal? failure2 #f)
      (check-equal? (eq? (.get fresh context) other) #t)
      (check-equal? (vector-ref count 0) 2)
      (completed!))

    (test-case "invalid fields refuse before policy and retain previous value"
      (defvalues (parent _calls _raw) (make-scenario))
      (defvalues (descriptor _contract count observed) (make-admission ScenarioContract allow))
      (.def (typo @ parent)
        config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instnace_type: "t3.medium"))))
      (defvalues (bad kept failure)
        (publish-checked parent typo descriptor (make-context (vector 0))))
      (check-refused parent bad kept failure)
      (check-equal? (metadata.failure-phase failure) 'source)
      (check-equal? (vector-ref count 0) 1)
      (check-equal? (vector-ref observed 0) #f)
      (completed!))

    (test-case "contextual policy refusal retains previous value"
      (defvalues (parent _calls _raw) (make-scenario))
      (defvalues (descriptor _contract count _seen)
        (make-admission ScenarioContract (lambda (_value _context) #f)))
      (defvalues (bad kept failure)
        (publish-checked parent parent descriptor (make-context (vector 0))))
      (check-refused parent bad kept failure)
      (check-equal? (vector-ref count 0) 1)
      (completed!))

    (test-case "revision changes during admission and stale context refuse"
      (defvalues (parent _calls _raw) (make-scenario))
      (def revision (vector 0))
      (def context (make-context revision))
      (defvalues (original _original-contract original-count _original-seen)
        (make-admission ScenarioContract allow))
      (defvalues (old-evidence old-next old-refusal)
        (publish-checked parent parent original context))
      (check-equal? old-refusal #f)
      (defvalues (descriptor _contract count _seen)
        (make-admission ScenarioContract
          (lambda (_value _context) (vector-set! revision 0 1) #t)))
      (defvalues (bad kept failure) (publish-checked old-next parent descriptor context))
      (check-refused old-next bad kept failure)
      (check-equal? (vector-ref count 0) 1)
      (def publication (.cc AdmissionPublication. contract: original context: context))
      (defvalues (bad-replay kept-replay replay-failure)
        (metadata.publish (.call publication .bind-evidence old-next)
          old-next (lambda (checked) (values old-evidence checked)) old-next))
      (check-refused old-next bad-replay kept-replay replay-failure)
      (check-equal? (vector-ref original-count 0) 1)
      (defvalues (bad2 kept2 failure2) (publish-checked parent parent descriptor context))
      (check-refused parent bad2 kept2 failure2)
      (check-equal? (vector-ref count 0) 1)
      (completed!))

    (test-case "fixed parent projection and missing logical network refuse"
      (defvalues (parent _calls _raw) (make-scenario))
      (def cached (.get parent resource))
      (defvalues (descriptor _contract count _seen) (make-admission ScenarioContract allow))
      (def context (make-context (vector 0)))
      (.def (stale @ parent)
        config: =>.+ (.o web: =>.+ (.o settings: =>.+ (.o instance_type: "t3.medium")))
        resource: cached)
      (defvalues (bad kept failure) (publish-checked parent stale descriptor context))
      (check-refused parent bad kept failure)
      (.def (missing @ parent)
        config: =>.+ (.o web: =>.+ (.o network-ref: 'missing)))
      (defvalues (bad2 kept2 failure2) (publish-checked parent missing descriptor context))
      (check-refused parent bad2 kept2 failure2)
      (check-equal? (vector-ref count 0) 2)
      (completed!))))
