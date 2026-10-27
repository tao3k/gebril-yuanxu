;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? check-exception test-suite)
        (only-in :std/error Error?)
        (only-in :clan/poo/object .o .def .ref .cc object?)
        (only-in :clan/poo/type Record String)
        (only-in :clan/poo/mop Bool make-instance element? TypeError?)
        :yuanxu/observability/testing-case
        (only-in :yuanxu/module-system/config yuanxu-module-interface-schema-index)
        :yuanxu/module-system/projection/option-objects
        :yuanxu/module-system/projection/option-validation)

(export module-option-objects-test)

(def module-option-objects-test
  (test-suite "Core Module option POO values"
    (yuanxu-test-case "ordinary candidates are checked by their selected native Slot"
      (def config (.o id: "enabled" value: #t source-module: 'module-a))
      (def schema
        (make-instance ModuleOptionSchema
          id: "enabled" source-module: 'module-a
          field: (.ref (.ref (Record enabled: [Bool constant: #t]) 'effective-slots) 'enabled)))
      (def receipt (yuanxu-module-option-schema-validation-receipt schema config))
      (check-equal? (object? config) #t)
      (check-equal? (element? ModuleOptionSchema schema) #t)
      (check-equal? (yuanxu-module-option-schema-rule schema) 'constant)
      (check-equal? (object? receipt) #t)
      (check-equal? (.ref receipt 'valid?) #t)
      (check-equal? (.ref receipt 'source-module) 'module-a))
    (yuanxu-test-case "schema keeps the effective Slot and its diagnostic metadata"
      (def field (.cc (.ref (.ref (Record endpoint: [String default: "localhost"])
                                  'effective-slots) 'endpoint)
                      metadata: '((owner . network))))
      (def schema (make-instance ModuleOptionSchema
                    id: "endpoint" source-module: 'network field: field))
      (check-equal? (eq? (.ref schema 'field) field) #t)
      (check-equal? (yuanxu-module-option-schema-metadata schema) '((owner . network)))
      (check-equal? (yuanxu-module-option-schema-value schema) "localhost")
      (check-equal? (.ref (make-instance ModuleOptionSchema
                           id: "endpoint" source-module: "network" field: field)
                         'source-module) "network")
      (check-exception (make-instance ModuleOptionSchema
                         id: "endpoint" source-module: 42 field: field) TypeError?)
      (check-exception (make-instance ModuleOptionSchema
                         id: "endpoint" source-module: 'network field: 42) TypeError?)
      (check-exception (make-instance ModuleOptionSchema
                         id: 'endpoint source-module: 'network field: field) TypeError?))
    (yuanxu-test-case "nonconstant native Type failures retain field path and contributor"
      (def field (.ref (.ref (Record endpoint: [String default: "localhost"]) 'effective-slots) 'endpoint))
      (def schema (make-instance ModuleOptionSchema
                    id: "endpoint" source-module: 'network field: field))
      (def bad (.o id: "endpoint" value: 42 source-module: 'user-config))
      (def receipt (yuanxu-module-option-schema-validation-receipt schema bad))
      (check-equal? (.ref receipt 'valid?) #f)
      (check-equal? (.ref receipt 'source-module) 'user-config)
      (check-equal? (.ref (car (.ref receipt 'messages)) 'path) '(endpoint)))
    (yuanxu-test-case "pure validation preserves order and typed outcomes"
      (def schema
        (make-instance ModuleOptionSchema
          id: "enabled" source-module: 'module-a
          field: (.ref (.ref (Record enabled: [Bool constant: #t]) 'effective-slots) 'enabled)))
      (def matched (.o id: "enabled" value: #t source-module: 'module-a))
      (def mismatched (.o id: "enabled" value: #f source-module: 'module-a))
      (def missing (.o id: "absent" value: 1 source-module: 'module-a))
      (def receipts
        (yuanxu-module-options-validate
          (lambda (id) (yuanxu-module-find-schema (list schema) id))
          (list matched mismatched missing)))
      (check-equal? (map (cut .ref <> 'code) receipts) '(ok constant-mismatch missing-schema))
      (check-equal? (map (cut .ref <> 'valid?) receipts) '(#t #f #f)))
    (yuanxu-test-case "missing declarations leave payloads cold and derived values are rechecked"
      (def schema
        (make-instance ModuleOptionSchema
          id: "enabled" source-module: 'module-a
          field: (.ref (.ref (Record enabled: [Bool constant: #t]) 'effective-slots) 'enabled)))
      (def parent (.o id: "enabled" value: #t source-module: 'user))
      (def parent-receipt (yuanxu-module-option-schema-validation-receipt schema parent))
      (.def (child @ parent) value: #f)
      (def missing (.o id: "absent" source-module: 'user
                      value: (error "unclaimed value forced")
                      metadata: (error "candidate annotation forced")))
      (def requested '())
      (def receipts
        (yuanxu-module-options-validate
          (lambda (id)
            (set! requested (append requested (list id)))
            (and (equal? id "enabled") schema))
          (list missing child)))
      (check-equal? requested '("absent" "enabled"))
      (check-equal? (map (cut .ref <> 'code) receipts) '(missing-schema constant-mismatch))
      (check-equal? (.ref parent-receipt 'valid?) #t)
      (check-equal? (.ref parent 'value) #t)
      (check-equal? (.ref child 'value) #f))
    (yuanxu-test-case "native diagnostic validation keeps issue identity and original exceptions"
      (def observed 0)
      (def annotation-reads 0)
      (def annotations '((owner . network)))
      (def issue (.o kind: 'domain-rejected path: '(endpoint)
                    details: (error "unselected diagnostic details forced")))
      (def failures (list issue))
      (def DomainString
        (.cc String .diagnose: (lambda (_ location)
                                (set! observed (+ observed 1)) failures)))
      (def slot (.ref (.ref (Record endpoint: [DomainString]) 'effective-slots) 'endpoint))
      (def field (.o (:: @ slot)
                    metadata: (begin (set! annotation-reads (+ annotation-reads 1)) annotations)))
      (def schema
        (make-instance ModuleOptionSchema id: "endpoint" source-module: 'network field: field))
      (check-equal? annotation-reads 0)
      (def config (.o id: "endpoint" source-module: 'user value: "localhost"))
      (def receipt (yuanxu-module-option-schema-validation-receipt schema config))
      (check-equal? observed 1)
      (check-equal? annotation-reads 1)
      (check-equal? (eq? (.ref receipt 'metadata) annotations) #t)
      (check-equal? annotation-reads 1)
      (check-equal? (eq? (car (.ref receipt 'messages)) issue) #t)
      (check-equal? (.ref receipt 'code) 'domain-rejected)
      (def BadString (.cc String .diagnose: (lambda (_ location) (list (.o kind: 'malformed)))))
      (def malformed
        (make-instance ModuleOptionSchema id: "endpoint" source-module: 'network
          field: (.ref (.ref (Record endpoint: [BadString]) 'effective-slots) 'endpoint)))
      (check-exception (yuanxu-module-option-schema-validation-receipt malformed config) Error?)
      (def original (.o reason: 'domain-check-failed))
      (def ThrowingString (.cc String .diagnose: (lambda (_ location) (raise original))))
      (def throwing
        (make-instance ModuleOptionSchema id: "endpoint" source-module: 'network
          field: (.ref (.ref (Record endpoint: [ThrowingString]) 'effective-slots) 'endpoint)))
      (check-equal? (eq? (with-catch identity
                           (lambda () (yuanxu-module-option-schema-validation-receipt throwing config)))
                        original) #t))
    (yuanxu-test-case "whole Record diagnostics include absent required fields without forcing optional Types"
      (def Sleeping
        (.cc String .diagnose: (lambda (_ path) (error "optional Type demanded"))
                    .element?: (lambda (_) (error "optional membership demanded"))))
      (def declaration (Record endpoint: [String] sleeping: [Sleeping optional: #t]))
      (def index (yuanxu-module-interface-schema-index declaration))
      (def (field-ref id) (hash-get index id))
      (def absent (yuanxu-module-config-validation-receipts declaration field-ref (.o) 'user))
      (check-equal? (map (cut .ref <> 'code) absent) '(missing-field))
      (check-equal? (.ref (car absent) 'id) "endpoint")
      (check-equal? (.ref (car (.ref (car absent) 'messages)) 'path) '(endpoint))
      (def present
        (yuanxu-module-config-validation-receipts declaration field-ref
          (.o endpoint: "localhost" unknown: (error "unknown payload forced")) 'user))
      (check-equal? (map (cut .ref <> 'code) present) '(ok missing-schema))
      (def closed
        (yuanxu-module-config-validation-receipts (.cc declaration sealed: #t) field-ref
          (.o endpoint: "localhost" unknown: (error "closed extra payload forced")) 'user))
      (check-equal? (map (cut .ref <> 'code) closed) '(ok unknown-field))
      (check-equal? (.ref (car (.ref (cadr closed) 'messages)) 'path) '(unknown)))
    (yuanxu-test-case "whole membership sees the final object and field diagnostics run once"
      (def field-checks 0)
      (def root-checks 0)
      (def CountedString
        (.cc String .diagnose: (lambda (value path)
                                (set! field-checks (+ field-checks 1)) '())))
      (def declaration
        (.cc (Record start: [CountedString] finish: [String])
          .element?: (lambda (candidate)
                       (set! root-checks (+ root-checks 1))
                       (equal? (.ref candidate 'start) (.ref candidate 'finish)))))
      (def index (yuanxu-module-interface-schema-index declaration))
      (def (field-ref id) (hash-get index id))
      (def parent (.o start: "same" finish: "same"))
      (def cached (yuanxu-module-config-validation-receipts declaration field-ref parent 'user))
      (check-equal? (map (cut .ref <> 'valid?) cached) '(#t #t))
      (check-equal? field-checks 1)
      (check-equal? root-checks 1)
      (.def (child @ parent) finish: "different")
      (def refused (yuanxu-module-config-validation-receipts declaration field-ref child 'user))
      (check-equal? field-checks 2)
      (check-equal? root-checks 2)
      (check-equal? (map (cut .ref <> 'code) refused) '(ok ok class-rejected))
      (check-equal? (.ref (caddr refused) 'id) #f)
      (check-equal? (.ref (car (.ref (caddr refused) 'messages)) 'path) '())
      (check-equal? (map (cut .ref <> 'valid?) cached) '(#t #t)))
    (yuanxu-test-case "grouping retains native diagnostic identity and requires no fabricated field for root errors"
      (def leaf (.o kind: 'leaf-refused path: '(endpoint nested)
                   details: (error "diagnostic extension forced")))
      (def root (.o kind: 'whole-refused path: '()))
      (def declaration
        (.cc (Record endpoint: [String]) .diagnose: (lambda (_ path) (list leaf root))))
      (def index (yuanxu-module-interface-schema-index declaration))
      (def receipts
        (yuanxu-module-config-validation-receipts declaration (cut hash-get index <>)
          (.o endpoint: "localhost") 'user))
      (check-equal? (map (cut .ref <> 'code) receipts) '(leaf-refused whole-refused))
      (check-equal? (eq? (car (.ref (car receipts) 'messages)) leaf) #t)
      (check-equal? (eq? (car (.ref (cadr receipts) 'messages)) root) #t)
      (def wrong
        (yuanxu-module-config-validation-receipts (Record endpoint: [String])
          (lambda (_) (error "root refusal looked up a field")) 42 'user))
      (check-equal? (map (cut .ref <> 'code) wrong) '(expected-object)))))
