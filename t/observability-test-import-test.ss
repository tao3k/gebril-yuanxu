;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualify the existing test macro's observation dependency, not a new runner.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :core/module-system/building/source-closure for-each-build-module)
        (only-in :core/module-system/building/test-projection
                 module-test-file-source module-test-execution)
        (only-in :core/observability/testing-fixture
                 poo-flow-test-fixture with-poo-flow-fixture)
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile poo-flow-test-checkpoint)
        (only-in :core/observability/memory poo-flow-debug-allocation-current?))
(export observability-test-import-test)

(def released 0)
(.def Resource
  .acquire: (lambda () 'resource)
  .release: (lambda (_value) (set! released (+ released 1))))
(.def (Observation @ poo-flow-default-testing-case-profile)
  identity: 'test/observation emit?: #t)

(def observability-test-import-test
  (test-suite "Test macros own bounded Observability"
    (test-case "a counter rollback invalidates later allocation evidence"
      (check-equal? (poo-flow-debug-allocation-current? #t 100 120) #t)
      (def current? (poo-flow-debug-allocation-current? #t 120 110))
      (check-equal? current? #f)
      (check-equal? (poo-flow-debug-allocation-current? current? 110 130) #f))
    (poo-flow-test-fixture "a fixture profile owns its phase receipt"
      profile: Observation (resource Resource)
      (def receipt (poo-flow-test-checkpoint 'selected-graph))
      (check-equal? (.get receipt policy label) 'test/observation)
      (check-equal? (.get receipt after phase) 'selected-graph))
    (poo-flow-test-fixture "fixtures load the existing watchdog without optional printers"
      (resource Resource)
      (def identities '())
      (for-each-build-module
        (core-import-module ':core/observability/testing-fixture)
        (lambda (context)
          (set! identities (cons (expander-context-id context) identities))))
      (check-equal? (and (memq 'core/observability/memory identities) #t) #t)
      (for-each
        (lambda (id) (check-equal? (memq id identities) #f))
        '(core/observability/debug core/observability/slot-debug
          core/module-system/building/test-observation
          clan/poo/debug clan/poo/type clan/poo/number)))
    (test-case "a fresh native worker qualifies the raw allocation counter"
      ;; A prior watchdog's lifetime can invalidate this VM counter stream.
      ;; Preserve the positive payload control in a fresh native test process;
      ;; rollback validity is checked independently above, never clamped to pass.
      (def source
        (module-test-file-source
          (list (path-expand "qualification/observability/raw-allocation-test.ss"
                            (path-directory (this-source-file))))))
      (check-equal? (.get (.call (module-test-execution source) .run) status) 0))
    (test-case "body failure preserves fixture cleanup"
      (def before released)
      (check-exception
        (with-poo-flow-fixture (resource Resource)
          (error "deliberate fixture failure")) error?)
      (check-equal? released (+ before 1)))))
