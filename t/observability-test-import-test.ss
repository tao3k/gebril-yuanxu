;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualify the existing test macro's observation dependency, not a new runner.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :tao3k/yuanxu/observability/testing-fixture
                 yuanxu-test-fixture with-yuanxu-fixture)
        (only-in :tao3k/yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile yuanxu-test-checkpoint)
        (only-in :tao3k/yuanxu/observability/memory yuanxu-debug-allocation-current?))
(export observability-test-import-test)

(def released 0)
(.def Resource
  .acquire: (lambda () 'resource)
  .release: (lambda (_value) (set! released (+ released 1))))
(.def (Observation @ yuanxu-default-testing-case-profile)
  identity: 'test/observation emit?: #t)

(def observability-test-import-test
  (test-suite "Test macros own bounded Observability"
    (test-case "a counter rollback invalidates later allocation evidence"
      (check-equal? (yuanxu-debug-allocation-current? #t 100 120) #t)
      (def current? (yuanxu-debug-allocation-current? #t 120 110))
      (check-equal? current? #f)
      (check-equal? (yuanxu-debug-allocation-current? current? 110 130) #f))
    (yuanxu-test-fixture "a fixture profile owns its phase receipt"
      profile: Observation (resource Resource)
      (def receipt (yuanxu-test-checkpoint 'selected-graph))
      (check-equal? (.get receipt policy label) 'test/observation)
      (check-equal? (.get receipt after phase) 'selected-graph))
    (yuanxu-test-fixture "fixtures load the existing watchdog without optional printers"
      (resource Resource)
      (def identities '())
      (def contract-identities '())
      (for-each
        (lambda (root)
          (for-each-build-module
            (core-import-module root)
            (lambda (context)
              (set! contract-identities
                (cons (expander-context-id context) contract-identities)))))
        '(:clan/poo/object :tao3k/yuanxu/observability/types))
      (for-each-build-module
        (core-import-module ':tao3k/yuanxu/observability/testing-fixture)
        (lambda (context)
          (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'tao3k/yuanxu/observability/memory identities) #t) #t)
      (for-each
        (lambda (id) (check-equal? (memq id identities) #f))
        '(tao3k/yuanxu/observability/debug tao3k/yuanxu/observability/slot-debug
          tao3k/yuanxu/module-system/building/test-observation
          clan/poo/debug))
      ;; Memory policy/receipt Contracts use Types after the refactor.
      ;; No additional Type family may enter beyond those required contracts.
      (for-each
        (lambda (id)
          (check-equal? (and (memq id identities) #t)
                        (and (memq id contract-identities) #t)))
        '(clan/poo/type clan/poo/number)))
    (test-case "body failure preserves fixture cleanup"
      (def before released)
      (check-exception
        (with-yuanxu-fixture (resource Resource)
          (error "deliberate fixture failure")) error?)
      (check-equal? released (+ before 1)))))
