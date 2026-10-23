;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Public binding and actual Core producer; no module adapter or receipt wrapper.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop element?)
        :clan/poo/object-contract
        (prefix-in :clan/poo/declarative-metadata metadata.)
        :yuanxu/modules/json-schema/contracts
        (only-in :yuanxu/object-types/contracts
          YuanxuContract. yuanxu-contract-admit
          yuanxu-classification-evidence
          yuanxu-validation-evidence-accepted?))
(export evidence-binding-test)

;; Small local schema; real provider-schema controls are a separate suite.
(def ConfigContract
  (schema-value-contract 'fixture/instance
    '((type . "object")
      (properties . ((instance_type . ((type . "string")))))
      (required . ("instance_type")) (additionalProperties . #f))))
(def ScenarioContract
  (.cc ProjectionContract. constraint: ConfigContract
       project: (lambda (scenario) (.get scenario config))))

(def Admission
  (.cc YuanxuContract.
    identity: 'fixture/scenario
    .classify:
    (lambda (candidate context)
      (let (issues (diagnose ScenarioContract candidate))
        (yuanxu-classification-evidence
          'fixture/scenario candidate (null? issues) issues context)))))

(def (evidence-view evidence)
  (.o subject: (.get evidence candidate)
      descriptor: (.get evidence admission-contract)
      context: (.get evidence context)))

(def AdmissionCall
  (metadata.contract
    (metadata.typed "final configuration" ScenarioContract)
    (metadata.predicate "accepted Core evidence with descriptor"
      (lambda (evidence)
        (and (yuanxu-validation-evidence-accepted? evidence)
             (.slot? evidence 'admission-contract))))
    (lambda (_atom _request _result) #t)
    metadata.truth))

(def (bind subject descriptor context (invocation AdmissionCall))
  (metadata.bind-evidence invocation subject descriptor context evidence-view))

(def (publish-admission previous subject descriptor context)
  (metadata.publish (bind subject descriptor context) previous
    (lambda (candidate)
      (values (yuanxu-contract-admit descriptor candidate context) candidate))
    subject))

;; Replay is a deliberately faulty executor. Success next-state must never leak
;; when its receipt fails the existing invocation relationship check.
(def (reject-replay previous subject descriptor context old-evidence)
  (defvalues (result next refusal)
    (metadata.publish (bind subject descriptor context) previous
      (lambda (_candidate) (values old-evidence subject)) subject))
  (check-equal? result #f)
  (check-equal? (eq? next previous) #t)
  (check-equal? (metadata.failure? refusal) #t)
  (check-equal? (metadata.failure-phase refusal) 'logic))

(.def (Parent @ [] config)
  config: (.o instance_type: "t3.small")
  resource: (.o instance_type: (.get config instance_type)))

(def Context
  (.o graph: (.o revision: 1) source-version: 'source-1 schema-version: 'schema-1))

(def evidence-binding-test
  (test-suite "Bound evidence through existing invocation and publication"
    (test-case "unified producer records the exact .admit descriptor"
      (def receipt (yuanxu-contract-admit Admission Parent Context))
      (check-equal? (yuanxu-validation-evidence-accepted? receipt) #t)
      (check-equal? (eq? (.get receipt admission-contract) Admission) #t)
      (check-equal? (eq? (.get receipt candidate) Parent) #t)
      (check-equal? (eq? (.get receipt context) Context) #t)
      (check-equal? (.get receipt contract-identity) 'fixture/scenario)
      (defvalues (result next refusal)
        (publish-admission Parent Parent Admission Context))
      (check-equal? refusal #f)
      (check-equal? (eq? next Parent) #t)
      (check-equal? (eq? (.get result admission-contract) Admission) #t))

    (test-case "same name does not make different contracts interchangeable"
      (def other (.cc Admission .obligations: (lambda (_candidate _context) '())))
      (def old (yuanxu-contract-admit Admission Parent Context))
      (check-equal? (.get other identity) (.get Admission identity))
      (check-equal? (eq? other Admission) #f)
      (check-equal? (yuanxu-validation-evidence-accepted?
                      (yuanxu-contract-admit other Parent Context)) #t)
      (reject-replay Parent Parent other Context old)
      (defvalues (fresh next refusal) (publish-admission Parent Parent other Context))
      (check-equal? refusal #f)
      (check-equal? (eq? (.get fresh admission-contract) other) #t)
      (check-equal? (eq? next Parent) #t))

    (test-case "an invalid descriptor reference cannot masquerade as accepted evidence"
      (def raw (.cc (yuanxu-contract-admit Admission Parent Context)
                   admission-contract: #f))
      (def previous (.cc Parent))
      (check-equal? (yuanxu-validation-evidence-accepted? raw) #f)
      (defvalues (result next refusal)
        (metadata.publish (bind Parent Admission Context) previous
          (lambda (_candidate) (values raw Parent)) Parent))
      (check-equal? result #f)
      (check-equal? (eq? next previous) #t)
      (check-equal? (metadata.failure-phase refusal) 'output))

    (test-case "cached parent does not supply a derived receiver's final value or evidence"
      (def cached (.get Parent resource instance_type))
      (def parent-receipt (yuanxu-contract-admit Admission Parent Context))
      (.def (Release @ Parent)
        config: =>.+ (.o instance_type: "t3.medium"))
      (check-equal? cached "t3.small")
      (check-equal? (.get Release resource instance_type) "t3.medium")
      (reject-replay Parent Release Admission Context parent-receipt)
      (defvalues (fresh next refusal) (publish-admission Parent Release Admission Context))
      (check-equal? refusal #f)
      (check-equal? (eq? next Release) #t)
      (check-equal? (eq? (.get fresh candidate) Release) #t)
      (check-equal? (.get (.get fresh candidate) resource instance_type) "t3.medium"))

    (test-case "Graph source and Schema changes each require current context evidence"
      (def old (yuanxu-contract-admit Admission Parent Context))
      (for-each
        (lambda (current)
          (reject-replay Parent Parent Admission current old)
          (defvalues (fresh next refusal) (publish-admission Parent Parent Admission current))
          (check-equal? refusal #f)
          (check-equal? (eq? next Parent) #t)
          (check-equal? (eq? (.get fresh context) current) #t))
        (list (.cc Context graph: (.o revision: 2))
              (.cc Context source-version: 'source-2)
              (.cc Context schema-version: 'schema-2))))

    (test-case "equal-looking but distinct context is conservatively re-admitted"
      (def current (.cc Context))
      (check-equal? (eq? current Context) #f)
      (reject-replay Parent Parent Admission current
                     (yuanxu-contract-admit Admission Parent Context)))

    (test-case "fresh rejected admission never publishes the proposed next value"
      (.def (Proposed @ Parent)
        config: =>.+ (.o instance_type: "t3.medium"))
      (def rejecting
        (.cc Admission .obligations:
          (lambda (_candidate _context) (list (.o kind: 'fixture-policy-refused)))))
      (check-equal? (eq? Proposed Parent) #f)
      (defvalues (result next refusal) (publish-admission Parent Proposed rejecting Context))
      (check-equal? result #f)
      (check-equal? (eq? next Parent) #t)
      (check-equal? (metadata.failure-phase refusal) 'output))

    (test-case "original invocation rule is preserved before the new binding rule"
      (def proposed (.cc Parent))
      (def guarded
        (.cc AdmissionCall
          meaning: (lambda (_atom _request _evidence) #f)
          rule: (metadata.atom 'original-policy)))
      (defvalues (result next refusal)
        (metadata.publish (bind proposed Admission Context guarded) Parent
          (lambda (candidate)
            (values (yuanxu-contract-admit Admission candidate Context) candidate)) proposed))
      (check-equal? result #f)
      (check-equal? (eq? next Parent) #t)
      (check-equal? (metadata.failure-phase refusal) 'logic))

    (test-case "binding identity does not claim authentication of copied evidence"
      (def other (.cc Admission))
      (def old (yuanxu-contract-admit Admission Parent Context))
      ;; Explicit limit: trusted-producer discipline is a premise. A caller can
      ;; forge ordinary POO fields; this control prevents an authentication claim.
      (def forged (.cc old admission-contract: other))
      (defvalues (result next refusal)
        (metadata.publish (bind Parent other Context) Parent
          (lambda (_candidate) (values forged Parent)) Parent))
      (check-equal? refusal #f)
      (check-equal? (eq? result forged) #t)
      (check-equal? (eq? next Parent) #t))))
