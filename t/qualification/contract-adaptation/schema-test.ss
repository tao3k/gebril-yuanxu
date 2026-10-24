;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Local closed schemas exercise existing compilation; not live AWS schemas.
(import :std/test :clan/poo/object :clan/poo/mop
        :clan/poo/object-contract ./fixture-schema ./receipt-fixture ./fixture-core
        :yuanxu/modules/json-schema/contracts
        (only-in :yuanxu/object-types/contracts yuanxu-validation-evidence-accepted?))
(export schema-test)

(def vpc-schema
  '((type . "object")
    (properties . ((cidr_block . ((type . "string")))
                   (tags . ((type . "object")
                            (additionalProperties . ((type . "string")))))))
    (required . ("cidr_block"))
    (additionalProperties . #f)))
(def instance-schema
  '((type . "object")
    (properties . ((ami . ((type . "string")))
                   (instance_type . ((type . "string")
                                     (enum . ("t3.small" "t3.medium"))))
                   (tags . ((type . "object")
                            (additionalProperties . ((type . "string")))))))
    (required . ("ami" "instance_type"))
    (additionalProperties . #f)))

(def Contracts (make-aws-profile-contracts vpc-schema instance-schema))
(def AWSContract (.get Contracts AWSProfileContract))

;; Consumer and its configuration are separate in this test, so resource
;; behavior is not an undeclared field inside the closed data contract.
(.def (Parent @ [] config)
  config:
  (.o region: "us-east-1"
      network: (.o cidr_block: "10.1.0.0/16"
                   tags: (.o Owner: "platform"))
      web: (.o ami: "ami-fixture"
               instance_type: "t3.small"
               network-ref: 'network
               tags: (.o Owner: "platform")))
  resources:
  (.o web:
      (.o instance_type: (.get config web instance_type)
          tags: (.get config web tags))))

(def schema-test
  (test-suite "Schema consumer with isolated POO PR source"
    (test-case "Type and compiled Schema adapt into one responsibilities map"
      (check-equal? (diagnose AWSContract (.get Parent config) '()) '())
      (check-equal? (element? AWSContract (.get Parent config)) #t)
      (check-equal? (eq? (.get AWSContract prepared-responsibilities network)
                         (.get Contracts NetworkProfileContract)) #t))
    (test-case "provider spelling survives projection and is refused"
      (.def (bad @ (.get Parent config))
        web: =>.+ (.o instnace_type: "t3.medium"))
      (def failures (diagnose AWSContract bad '()))
      (check-equal? (pair? failures) #t)
      (check-equal? (.get (car failures) kind) 'schema-rejected)
      (check-equal? (.get (car failures) path) '(web instnace_type))
      (check-equal? (element? AWSContract bad) #f))
    (test-case "wrong reference Type fails before root relation"
      (.def (bad @ (.get Parent config)) web: =>.+ (.o network-ref: 7))
      (check-equal? (.get (car (diagnose AWSContract bad '())) kind) 'type-rejected)
      (check-equal? (.get (car (diagnose AWSContract bad '())) path) '(web network-ref)))
    (test-case "absent reference field and unresolved target have distinct errors"
      (def web-without-reference
        (.o ami: "ami-fixture" instance_type: "t3.small"))
      (.def (missing-field @ (.get Parent config)) web: web-without-reference)
      (.def (missing-target @ (.get Parent config))
        web: =>.+ (.o network-ref: 'missing))
      (check-equal? (.get (car (diagnose AWSContract missing-field '())) kind) 'missing-field)
      (check-equal? (.get (car (diagnose AWSContract missing-target '())) kind)
                    'unresolved-network-reference))
    (test-case "Schema value violation is not mistaken for valid ancestry"
      (.def (bad @ (.get Parent config)) network: =>.+ (.o cidr_block: 42))
      (check-equal? (element? AWSContract bad) #f))
    (test-case "parent resources cached before child edit still use final child values"
      (def parent-type (.get Parent resources web instance_type))
      (def parent-tags (.get Parent resources web tags))
      (def parent-value (.get Parent config))
      (def parent-view (.o root: parent-value schema-generation: 'fixture/schema-1))
      (def parent-receipt (admit-fixture AWSContract parent-value parent-view))
      (.def (Release @ Parent)
        config: =>.+
        (.o web: =>.+
            (.o instance_type: "t3.medium"
                tags: =>.+ (.o Environment: "production"))))
      (def child-value (.get Release config))
      (def child-view (.o root: child-value schema-generation: 'fixture/schema-1))
      (check-equal? parent-type "t3.small")
      (check-equal? (.get Release resources web instance_type) "t3.medium")
      (check-equal? (.get Release resources web tags Owner) "platform")
      (check-equal? (.get Release resources web tags Environment) "production")
      (check-equal? (.slot? parent-tags 'Environment) #f)
      (check-equal? (diagnose AWSContract child-value '()) '())
      (check-equal? (fixture-current? parent-receipt AWSContract parent-value parent-view) #t)
      (check-equal? (fixture-current? parent-receipt AWSContract child-value child-view) #f)
      (def child-receipt (admit-fixture AWSContract child-value child-view))
      (check-equal? (fixture-current? child-receipt AWSContract child-value child-view) #t)
      (check-equal? (eq? (.get child-receipt candidate) child-value) #t)
      (def changed-schema (.o root: child-value schema-generation: 'fixture/schema-2))
      (check-equal? (fixture-current? child-receipt AWSContract child-value changed-schema) #f)
      ;; Negative control: a fixed parent result really remains stale.
      (check-equal? parent-type "t3.small")
      (check-equal? (equal? parent-type (.get Release resources web instance_type)) #f))
    (test-case "an invalid child is not accepted by a valid parent's receipt"
      (def parent-view (.o generation: 'parent))
      (def parent-receipt (admit-fixture AWSContract (.get Parent config) parent-view))
      (.def (bad @ (.get Parent config)) web: =>.+ (.o network-ref: 'missing))
      (def bad-view (.o generation: 'child))
      (check-equal? (fixture-current? parent-receipt AWSContract bad bad-view) #f)
      (check-equal? (.get (admit-fixture AWSContract bad bad-view) accepted?) #f))
    (test-case "existing Core admission accepts final values and rejects stale fixture snapshots"
      (def parent-value (.get Parent config))
      (def graph (.o identity: 'fixture/selected-graph))
      (def parent-snapshot
        (.o effective-root: parent-value profile-contract: AWSContract
            selected-graph: graph source-generation: 'source-1 schema-generation: 'schema-1))
      (def parent-evidence
        (admit-effective-configuration AWSContract parent-value parent-snapshot))
      (check-equal? (yuanxu-validation-evidence-accepted? parent-evidence) #t)
      (check-equal? (configuration-evidence-current? parent-evidence parent-snapshot) #t)
      ;; Force the parent consumer before creating the derived configuration.
      (check-equal? (.get Parent resources web instance_type) "t3.small")
      (.def (child @ Parent)
        config: =>.+ (.o web: =>.+ (.o instance_type: "t3.medium")))
      (def child-value (.get child config))
      (def child-snapshot
        (.o effective-root: child-value profile-contract: AWSContract
            selected-graph: graph source-generation: 'source-2 schema-generation: 'schema-1))
      (check-equal? (.get child resources web instance_type) "t3.medium")
      (check-equal? (configuration-evidence-current? parent-evidence child-snapshot) #f)
      (def child-evidence
        (admit-effective-configuration AWSContract child-value child-snapshot))
      (check-equal? (configuration-evidence-current? child-evidence child-snapshot) #t)
      (check-equal? (eq? (.get child-evidence candidate) child-value) #t)
      (def schema-revision (.cc child-snapshot 'schema-generation 'schema-2))
      (check-equal? (configuration-evidence-current? child-evidence schema-revision) #f)
      (.def (bad @ child-value) web: =>.+ (.o network-ref: 'missing))
      (def bad-snapshot (.cc child-snapshot 'effective-root bad))
      (check-equal? (yuanxu-validation-evidence-accepted?
                     (admit-effective-configuration AWSContract bad bad-snapshot)) #f)
      (check-exception
        (admit-effective-configuration AWSContract child-value parent-snapshot) error?))
    (test-case "unselected catalog entry is not evaluated"
      (def demands 0)
      (def catalog (.o selected: (.get Parent config)
                      unused: (begin (set! demands (+ demands 1))
                                     (error "unselected fixture branch forced"))))
      (check-equal? (diagnose AWSContract (.get catalog selected) '()) '())
      (check-equal? demands 0))
    (test-case "unsupported Schema constraints refuse construction"
      (check-exception
        (schema-value-contract 'fixture/unsupported
          '((type . "string") (fixtureUnknownKeyword . #t)))
        error?))))
