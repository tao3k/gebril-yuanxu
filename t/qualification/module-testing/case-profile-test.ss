;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Child-process probes only; module authors do not need profile declarations.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-resolve-identifier core-context-root
                 feature-binding? __module-registry current-expander-context
                 make-top-context eval-syntax)
        (only-in :yuanxu/observability/testing-fixture
                 yuanxu-test-fixture with-yuanxu-fixture)
        (only-in :yuanxu/observability/testing-case yuanxu-test-observe
                 yuanxu-selected-testing-case-profile))
(export module-case-child-test)
(def observed?
  (feature-binding?
    (core-resolve-identifier 'yuanxu-module-test-observation 0 (core-context-root))))
(def traced?
  (feature-binding?
    (core-resolve-identifier 'yuanxu-module-test-trace 0 (core-context-root))))
(def released 0)
(.def Resource
  .acquire: void
  .release: (lambda (_) (set! released (+ released 1))))
(def (adapter-loaded?)
  ;; Source-evaluated modules live in the expander registry, not necessarily
  ;; the runtime loader's compiled-module registry. This is a read-only probe.
  (and (hash-get __module-registry 'yuanxu/module-system/building/test-observation) #t))
(def module-case-child-test
  (test-suite "Native feature selects the Case profile at execution"
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
          (eval-syntax '(import :yuanxu/module-system/source/admission))
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
          (eval-syntax '(import :yuanxu/module-system/source/admission))
          (check-equal? (eval-syntax '(current-module-source-observer)) #f))))))
