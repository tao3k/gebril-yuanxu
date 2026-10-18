;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :clan/poo/mop
        (only-in :clan/poo/type String)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        :clan/poo/object-contract ./receipt-fixture)
(export generic-test)

(def generic-test
  (test-suite "Public POO contracts without Core imports"
    (test-case "existing Type adapts to responsibilities"
      (def contract (.cc ObjectContract. 'identity 'fixture/name
                        'responsibilities (.o name: String)))
      (check-equal? (element? contract (.o name: "web")) #t)
      (check-equal? (diagnose contract (.o name: "web") '()) '())
      (check-equal? (element? contract (.o name: 7)) #f)
      (check-equal? (.get (car (diagnose contract (.o name: 7) '())) path) '(name))
      (check-equal? (.get (car (diagnose contract (.o) '())) kind) 'missing-field))
    (test-case "closed fields reject spelling without demanding the unknown value"
      (def forced 0)
      (def contract (.cc ObjectContract. 'identity 'fixture/name
                        'responsibilities (.o name: String)))
      (def bad (.o name: "web" naem: (begin (set! forced (+ forced 1)) "bad")))
      (check-equal? (map (cut .get <> kind) (diagnose contract bad '())) '(unknown-field))
      (check-equal? forced 0))
    (test-case "structural conformance is distinct from required ancestry"
      (def base (.o name: "base"))
      (def contract (.cc ObjectContract. 'identity 'fixture/name
                        'responsibilities (.o name: String)))
      (def nominal (.cc contract 'required-prototype base))
      (check-equal? (element? contract (.o name: "independent")) #t)
      (check-equal? (element? nominal (.o name: "independent")) #f)
      (.def (child @ base) name: "child")
      (check-equal? (element? nominal child) #t)
      (def unrelated (.o name: (error "must not demand rejected ancestor fields")))
      (check-equal? (.get (car (diagnose nominal unrelated '())) kind) 'prototype-mismatch))
    (test-case "cached parent responsibility map does not mask child refinement"
      (def parent (.cc ObjectContract. 'identity 'fixture/value
                      'responsibilities (.o value: String)))
      (def parent-map (.get parent prepared-responsibilities))
      (.def (child @ parent) responsibilities: =>.+ (.o value: Bool))
      (check-equal? (element? parent (.o value: "text")) #t)
      (check-equal? (element? child (.o value: #t)) #t)
      (check-equal? (element? child (.o value: "text")) #f)
      (check-equal? (eq? parent-map (.get child prepared-responsibilities)) #f))
    (test-case "existing PR metadata lifts the Type and checks invocation input"
      (def contract (.cc ObjectContract. 'identity 'fixture/name
                        'responsibilities (.o name: String)))
      (def call-contract
        (metadata.contract (metadata.typed "named object" contract)
                           (metadata.typed "boolean" Bool)
                           (lambda (_atom _args _result) #t) metadata.truth))
      (def calls 0)
      (def (execute _value) (set! calls (+ calls 1)) (values #t 'state))
      (defvalues (result state)
        (metadata.invoke call-contract execute (.o name: "web")))
      (check-equal? result #t)
      (check-equal? state 'state)
      (check-exception (metadata.invoke call-contract execute (.o name: 7))
                       metadata.failure?)
      (check-equal? calls 1))
    (test-case "inherited resource slots use child values after parent demand"
      (def demands 0)
      (.def (parent @ [] name)
        name: "base"
        resource: (.o value: (begin (set! demands (+ demands 1)) name)))
      (def cached (.get parent resource value))
      (.def (child @ parent) name: "release")
      (check-equal? cached "base")
      (check-equal? (.get child resource value) "release")
      (check-equal? demands 2)
      (def contract (.cc ObjectContract. 'identity 'fixture/name
                        'responsibilities (.o name: String)))
      (def first-view (.o generation: 1))
      (def next-view (.o generation: 2))
      (def first (admit-fixture contract (.o name: cached) first-view))
      (def effective (.o name: (.get child resource value)))
      (check-equal? (fixture-current? first contract effective next-view) #f)
      (def fresh (admit-fixture contract effective next-view))
      (check-equal? (fixture-current? fresh contract effective next-view) #t))
    (test-case "unexpected callback exceptions remain exceptions"
      (def broken (.cc ObjectContract. 'identity 'fixture/broken
                       'obligations (lambda (_value _path) (error "fixture callback bug"))))
      (check-exception (diagnose broken (.o) '()) error?))))
