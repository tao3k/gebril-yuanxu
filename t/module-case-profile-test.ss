;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Official -D features select the profile in this std/test module; no child Harness.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-resolve-identifier core-context-root
                 feature-binding? __module-registry current-expander-context
                 make-top-context eval-syntax)
        (only-in :tao3k/yuanxu/observability/testing-fixture
                 yuanxu-test-fixture with-yuanxu-fixture)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-observe
                 yuanxu-selected-testing-case-profile yuanxu-test-case/with))
(export module-case-profile-test)
(def observed?
  (feature-binding?
    (core-resolve-identifier 'yuanxu-module-test-observation 0 (core-context-root))))
(def traced?
  (feature-binding?
    (core-resolve-identifier 'yuanxu-module-test-trace 0 (core-context-root))))
(def released 0)
(def invocation-events '())
(def body-failure (gensym 'case-body-failure))
(def (invocation-event value)
  (set! invocation-events (cons value invocation-events)))
(.def InvocationProfile
  .run: (begin
          (invocation-event 'lookup)
          (lambda (self label thunk)
            (check-eq? self InvocationProfile)
            (check-equal? label "factored Case keeps evaluation order")
            (invocation-event 'call)
            (def value
              (with-catch
                (lambda (failure)
                  (check-eq? failure body-failure)
                  (invocation-event 'caught)
                  'expected-failure)
                thunk))
            (values value 'original-receipt))))
(.def Resource
  .acquire: void
  .release: (lambda (_) (set! released (+ released 1))))
(def (adapter-loaded?)
  ;; Source-evaluated modules live in the expander registry, not necessarily
  ;; the runtime loader's compiled-module registry. This is a read-only probe.
  (and (hash-get __module-registry 'tao3k/yuanxu/module-system/building/test-observation) #t))
(def module-case-profile-test
  (test-suite "Runtime feature selects the Case profile at execution"
    (test-case "Case registration leaves profile and body unevaluated"
      (check-equal? invocation-events '())
      (set! invocation-events '()))
    (yuanxu-test-case/with
      (begin (invocation-event 'profile) InvocationProfile)
      "factored Case keeps evaluation order"
      (invocation-event 'body)
      (raise body-failure))
    (test-case "Case invokes the original method and retains the original fault"
      (check-equal? (reverse invocation-events)
                    '(profile lookup call body caught)))
    (test-case "discovery never demands the module observer"
      (check-equal? (adapter-loaded?) #f))
    (yuanxu-test-fixture "fixture automatically receives the selected policy"
      (resource Resource)
      (check-equal? (adapter-loaded?) observed?)
      (check-equal? (yuanxu-test-observe 'child-probe) (if observed? 1 0))
      (when observed?
        (check-equal? (.get (yuanxu-selected-testing-case-profile) trace-enabled?) traced?)
        (when traced? (yuanxu-test-observe 'child-trace))
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :tao3k/yuanxu/module-system/source/admission))
          (def observer (eval-syntax '(current-module-source-observer)))
          (check-equal? (procedure? observer) #t)
          (observer 'source-probe 2)
          (check-equal? (yuanxu-test-observe 'source-probe 0) 2)))
      (def before released)
      (check-exception
        (with-yuanxu-fixture (inner Resource) (error "deliberate failure")) error?)
      (check-equal? released (+ before 1)))
    (yuanxu-test-fixture "each Case has independent observation totals"
      (resource Resource)
      (check-equal? (yuanxu-test-observe 'child-probe 0) 0))
    (test-case "fixtures cleaned up and the adapter remains absent when disabled"
      (check-equal? released 3)
      (check-equal? (adapter-loaded?) observed?)
      (check-equal? (yuanxu-test-observe 'child-probe) 0)
      (when observed?
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :tao3k/yuanxu/module-system/source/admission))
          (check-equal? (eval-syntax '(current-module-source-observer)) #f))))))
